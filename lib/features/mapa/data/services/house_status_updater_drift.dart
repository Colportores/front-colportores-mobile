import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../../agenda/domain/entities/estado_agenda.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/domain/entities/visita.dart';
import '../../../cobranzas/data/datasources/cobro_valido.dart';
import '../../../ventas/data/datasources/estado_de_devolucion.dart';
import '../../../ventas/data/datasources/estado_de_entrega.dart';
import '../../domain/entities/color_house_status.dart';
import '../../domain/entities/house_status.dart';
import '../../domain/services/calculador_color_casa.dart';
import '../../domain/services/house_status_updater.dart';
import '../models/house_status_model.dart';
import '../models/ubicacion_model.dart';

/// [HouseStatusUpdater] sobre las tablas de la DB cifrada: junta los hechos de la casa (las agendas
/// pendientes y las visitas de todos sus espacios), le pregunta el color a [CalculadorColorCasa] y
/// deja la fila de `house_status` como corresponde, encolando su subida.
///
/// **Es la única que escribe `house_status`** (ADR-003). Corre en la transacción de quien la llama
/// —Drift une una transacción anidada a la de afuera—, así que o se guardan la escritura de negocio,
/// la fila de la cache y su job de sync, o ninguno. Si no la llaman desde una transacción, abre la
/// suya.
///
/// Mira solo los **espacios activos** de la ubicación (la baja de un depto saca sus visitas del
/// color, no del historial): una visita que ya pasó sigue contando aunque su persona esté dada de
/// baja o no tenga persona. Las agendas y visitas dadas de baja no cuentan. De cada visita lleva
/// el resultado y su `fecha`: entre entrevista dada, sin contestar y rechazo manda la más reciente.
final class HouseStatusUpdaterDrift implements HouseStatusUpdater {
  /// [_encolador] se pasa como `encolador:` (parámetro nombrado privado, Dart ≥ 3.10).
  HouseStatusUpdaterDrift(this._db, {required this._encolador});

  final AppDatabase _db;
  final EncoladorSync _encolador;

  @override
  Future<HouseStatus?> recalcular(
    String ubicacionId, {
    required DateTime ahora,
    required String colportorId,
  }) => _db.transaction(() async {
    final instante = instanteMs(ahora);
    final ubicacion = await (_db.select(
      _db.ubicaciones,
    )..where((u) => u.id.equals(ubicacionId))).getSingleOrNull();
    if (ubicacion == null || ubicacion.deletedAt != null) return null;

    final color = CalculadorColorCasa.calcular(
      agendasPendientes: await _agendasPendientes(ubicacionId),
      resultadosDeVisitas: await _resultadosDeVisitas(ubicacionId),
      ventas: await _ventas(ubicacionId),
    );
    final existente = await _fila(ubicacionId);

    if (color == null) {
      // Sin ningún estado que la pinte, la casa vuelve a «Sin visita»: es la ausencia de fila.
      if (existente == null || existente.deletedAt != null) return null;
      await _escribir(
        ubicacionId,
        HouseStatusesCompanion(deletedAt: Value(instante), updatedAt: Value(instante)),
      );
      await _encolar(OperacionSync.delete, ubicacionId);
      return null;
    }

    if (existente == null) {
      await _db
          .into(_db.houseStatuses)
          .insert(
            HouseStatusesCompanion.insert(
              ubicacionId: ubicacionId,
              lat: ubicacion.lat,
              lon: ubicacion.lon,
              tipoUbicacion: ubicacion.tipo,
              color: color.codigo,
              prioridad: color.prioridad,
              createdAt: instante,
              updatedAt: instante,
              createdBy: Value(colportorId),
            ),
          );
      return _encolar(OperacionSync.insert, ubicacionId);
    }

    final sinCambio =
        existente.deletedAt == null &&
        existente.color == color.codigo &&
        existente.lat == ubicacion.lat &&
        existente.lon == ubicacion.lon &&
        existente.tipoUbicacion == ubicacion.tipo;
    if (sinCambio) return _aEntidad(existente);

    await _escribir(
      ubicacionId,
      HouseStatusesCompanion(
        lat: Value(ubicacion.lat),
        lon: Value(ubicacion.lon),
        tipoUbicacion: Value(ubicacion.tipo),
        color: Value(color.codigo),
        prioridad: Value(color.prioridad),
        updatedAt: Value(instante),
        deletedAt: const Value(null),
      ),
    );
    return _encolar(OperacionSync.update, ubicacionId);
  });

  /// Los espacios activos de [ubicacionId], como subconsulta. Las agendas y las visitas cuelgan del
  /// espacio (migración 0068/0069), con o sin persona.
  JoinedSelectStatement<HasResultSet, dynamic> _espaciosDe(String ubicacionId) =>
      _db.selectOnly(_db.espacios)
        ..addColumns([_db.espacios.id])
        ..where(_db.espacios.ubicacionId.equals(ubicacionId) & _db.espacios.deletedAt.isNull());

  Future<List<TipoAgenda>> _agendasPendientes(String ubicacionId) async {
    final filas =
        await (_db.select(_db.agendas)..where(
              (a) =>
                  a.espacioId.isInQuery(_espaciosDe(ubicacionId)) &
                  a.estado.equals(EstadoAgenda.programada.codigo) &
                  a.deletedAt.isNull(),
            ))
            .get();
    return [for (final fila in filas) TipoAgenda.desdeCodigo(fila.tipo)];
  }

  /// El resultado y la fecha de cada visita viva de la casa. Una venta que se devolvió por completo
  /// (HU-VEN-004) suma una «entrevista dada» con la fecha de su última devolución: la persona se
  /// entrevistó y no se quedó con nada, así que la casa vuelve a «entrevista dada» (verde liso) salvo
  /// que haya algo más urgente o una visita posterior (ADR-003).
  Future<List<ResultadoDeVisitaFechado>> _resultadosDeVisitas(String ubicacionId) async {
    final filas = await (_db.select(
      _db.visitas,
    )..where((v) => v.espacioId.isInQuery(_espaciosDe(ubicacionId)) & v.deletedAt.isNull())).get();
    return [
      for (final fila in filas)
        (resultado: TipoResultadoVisita.desdeCodigo(fila.tipoResultado), fecha: fila.fecha),
      for (final fecha in (await _ventasDevueltasPorCompleto(ubicacionId)).values)
        (resultado: TipoResultadoVisita.entrevista, fecha: fecha),
    ];
  }

  /// Las ventas vivas de la casa: las ventas cuelgan del vínculo persona ↔ espacio, y el espacio tiene
  /// que seguir activo.
  Future<List<VentaFila>> _ventasVivas(String ubicacionId) {
    final vinculos = _db.selectOnly(_db.espacioPersonas)
      ..addColumns([_db.espacioPersonas.id])
      ..where(_db.espacioPersonas.espacioId.isInQuery(_espaciosDe(ubicacionId)));
    return (_db.select(
      _db.ventas,
    )..where((v) => v.espacioPersonaId.isInQuery(vinculos) & v.deletedAt.isNull())).get();
  }

  /// Cada venta viva de la casa con lo que el cliente se queda y lo que lleva pagado (HU-VEN-001,
  /// HU-COB-001, HU-VEN-004): son las cuentas de [CuentaDeLaVenta], la misma fórmula del saldo —lo
  /// devuelto baja lo que se queda y lo reembolsado baja lo pagado—. Los cobros dados de baja no
  /// cuentan (`CobroValido`). Una venta devuelta por completo no pinta por sí sola (queda en 0).
  Future<List<({int montoCentavos, int cobradoCentavos, bool entregada})>> _ventas(
    String ubicacionId,
  ) async {
    final filas = await _ventasVivas(ubicacionId);
    final devoluciones = await EstadoDeDevolucion.resumenesDe(_db, [for (final f in filas) f.id]);
    final salida = <({int montoCentavos, int cobradoCentavos, bool entregada})>[];
    for (final fila in filas) {
      final cuenta = (devoluciones[fila.id] ?? ResumenDeDevoluciones.ninguna).cuentaDe(
        montoTotalCentavos: fila.montoTotal,
        cobradoCentavos: await CobroValido.cobradoDe(_db, fila.id),
      );
      // Entregada = todo lo vendido y no devuelto tiene su entrega hecha (HU-VEN-002,
      // `EstadoDeEntrega`): la misma cuenta que usa «Entregar ahora». Sin entrega registrada, la venta
      // sigue pendiente.
      salida.add((
        montoCentavos: cuenta.seQuedaConCentavos,
        cobradoCentavos: cuenta.yaPagoCentavos,
        entregada: await EstadoDeEntrega.estaEntregada(_db, fila.id),
      ));
    }
    return salida;
  }

  /// Las ventas vivas de la casa con plata que se devolvieron por completo, con la fecha de su última
  /// devolución.
  Future<Map<String, DateTime>> _ventasDevueltasPorCompleto(String ubicacionId) async {
    final filas = (await _ventasVivas(ubicacionId)).where((v) => v.montoTotal > 0).toList();
    final devoluciones = await EstadoDeDevolucion.resumenesDe(_db, [for (final f in filas) f.id]);
    return {
      for (final fila in filas)
        if (devoluciones[fila.id] case final resumen?)
          if (resumen.todoDevuelto && resumen.ultimaFecha != null) fila.id: resumen.ultimaFecha!,
    };
  }

  Future<HouseStatusFila?> _fila(String ubicacionId) => (_db.select(
    _db.houseStatuses,
  )..where((h) => h.ubicacionId.equals(ubicacionId))).getSingleOrNull();

  Future<void> _escribir(String ubicacionId, HouseStatusesCompanion cambios) => (_db.update(
    _db.houseStatuses,
  )..where((h) => h.ubicacionId.equals(ubicacionId))).write(cambios);

  /// Lee la fila ya escrita y encola [operacion] con la fila entera (la `sync_version` esperada de
  /// un `update` o un `delete` sale del payload).
  Future<HouseStatus> _encolar(OperacionSync operacion, String ubicacionId) async {
    final entidad = _aEntidad((await _fila(ubicacionId))!);
    await _encolador.encolar(
      'house_status',
      operacion,
      HouseStatusModel.fromEntity(entidad).toJson(),
    );
    return entidad;
  }

  static HouseStatus _aEntidad(HouseStatusFila fila) => HouseStatus(
    ubicacionId: fila.ubicacionId,
    lat: fila.lat,
    lon: fila.lon,
    tipoUbicacion: UbicacionModel.tipoDesdeCodigo(fila.tipoUbicacion),
    color: ColorHouseStatus.desdeCodigo(fila.color),
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );
}
