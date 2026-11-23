import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../domain/entities/color_house_status.dart';
import '../../domain/entities/house_status.dart';
import '../../domain/services/house_status_updater.dart';
import '../models/house_status_model.dart';
import '../models/ubicacion_model.dart';
import 'hechos_del_color_drift.dart';

/// [HouseStatusUpdater] sobre las tablas de la DB cifrada: junta los hechos de la casa (las agendas
/// pendientes, las visitas y las ventas de todos sus espacios, con [HechosDelColorDrift], que le
/// pregunta el color a `CalculadorColorCasa`) y deja la fila de `house_status` como corresponde,
/// encolando su subida.
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

    final color = await HechosDelColorDrift(
      _db,
    ).color(activos: () => _espaciosDe(ubicacionId), deBaja: () => _deptosDeBajaDe(ubicacionId));
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

  /// Los espacios **dados de baja** de [ubicacionId] (los deptos): lo que se debe en ellos sigue
  /// contando para el color (decisión de Cristian, 03/11, «Color y baja»).
  JoinedSelectStatement<HasResultSet, dynamic> _deptosDeBajaDe(String ubicacionId) =>
      _db.selectOnly(_db.espacios)
        ..addColumns([_db.espacios.id])
        ..where(_db.espacios.ubicacionId.equals(ubicacionId) & _db.espacios.deletedAt.isNotNull());

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
