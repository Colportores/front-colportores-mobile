import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../agenda/domain/entities/estado_agenda.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/domain/entities/visita.dart';
import '../../../cobranzas/data/datasources/cobro_valido.dart';
import '../../../ventas/data/datasources/estado_de_devolucion.dart';
import '../../../ventas/data/datasources/estado_de_entrega.dart';
import '../../domain/entities/color_house_status.dart';
import '../../domain/services/calculador_color_casa.dart';

/// Una subconsulta con los ids de un grupo de espacios (`SELECT espacio.id FROM espacio WHERE …`). Es
/// una fábrica y no la consulta: cada uso arma la suya.
typedef EspaciosDelColor = JoinedSelectStatement<HasResultSet, dynamic> Function();

/// Junta, de la DB local, los hechos que pintan un lugar —las agendas pendientes, las visitas y las
/// ventas con sus cobros, entregas y devoluciones— y le pregunta el color a [CalculadorColorCasa]. Solo
/// lee.
///
/// Es la misma cuenta para una casa entera (`HouseStatusUpdaterDrift`, que la guarda en
/// `house_status`) y para un depto solo (`EstadosDeLosDeptosDrift`, la fila del depto en la hoja del
/// edificio, vista 39 C·09): cambia solo qué espacios se miran. Así el depto y el edificio nunca dicen
/// cosas distintas, y el edificio toma el estado más urgente de sus deptos (decisión de Cristian,
/// 23/10, «Color edificio»).
final class HechosDelColorDrift {
  HechosDelColorDrift(this._db);

  final AppDatabase _db;

  /// El color de lo que cuelga de [activos] (los espacios que cuentan enteros) o `null` si nada lo
  /// pinta («Sin visita»). De [deBaja] (los deptos dados de baja de la casa) cuentan solo las ventas que
  /// todavía se deben (decisión de Cristian, 03/11, «Color y baja»).
  Future<ColorHouseStatus?> color({
    required EspaciosDelColor activos,
    EspaciosDelColor? deBaja,
  }) async => CalculadorColorCasa.calcular(
    agendasPendientes: await _agendasPendientes(activos),
    resultadosDeVisitas: await _resultadosDeVisitas(activos),
    ventas: await _ventas(activos, deBaja),
  );

  Future<List<TipoAgenda>> _agendasPendientes(EspaciosDelColor espacios) async {
    final filas =
        await (_db.select(_db.agendas)..where(
              (a) =>
                  a.espacioId.isInQuery(espacios()) &
                  a.estado.equals(EstadoAgenda.programada.codigo) &
                  a.deletedAt.isNull(),
            ))
            .get();
    return [for (final fila in filas) TipoAgenda.desdeCodigo(fila.tipo)];
  }

  /// El resultado y la fecha de cada visita viva. Una venta que se devolvió por completo (HU-VEN-004)
  /// suma una «entrevista dada» con la fecha de su última devolución: la persona se entrevistó y no se
  /// quedó con nada, así que vuelve a «entrevista dada» (verde liso) salvo que haya algo más urgente o
  /// una visita posterior (ADR-003).
  Future<List<ResultadoDeVisitaFechado>> _resultadosDeVisitas(EspaciosDelColor espacios) async {
    final filas = await (_db.select(
      _db.visitas,
    )..where((v) => v.espacioId.isInQuery(espacios()) & v.deletedAt.isNull())).get();
    return [
      for (final fila in filas)
        (resultado: TipoResultadoVisita.desdeCodigo(fila.tipoResultado), fecha: fila.fecha),
      for (final fecha in (await _ventasDevueltasPorCompleto(espacios)).values)
        (resultado: TipoResultadoVisita.entrevista, fecha: fecha),
    ];
  }

  /// Las ventas vivas de [espacios]: las ventas cuelgan del vínculo persona ↔ espacio.
  /// [soloVinculosVivos] cuenta solo las personas vinculadas que siguen vivas (lo que hace el saldo de
  /// la ubicación con los deptos de baja).
  Future<List<VentaFila>> _ventasVivasDe(
    EspaciosDelColor espacios, {
    bool soloVinculosVivos = false,
  }) {
    final vinculos = _db.selectOnly(_db.espacioPersonas)
      ..addColumns([_db.espacioPersonas.id])
      ..where(
        soloVinculosVivos
            ? _db.espacioPersonas.espacioId.isInQuery(espacios()) &
                  _db.espacioPersonas.deletedAt.isNull()
            : _db.espacioPersonas.espacioId.isInQuery(espacios()),
      );
    return (_db.select(
      _db.ventas,
    )..where((v) => v.espacioPersonaId.isInQuery(vinculos) & v.deletedAt.isNull())).get();
  }

  /// Cada venta viva con lo que el cliente se queda y lo que lleva pagado (HU-VEN-001, HU-COB-001,
  /// HU-VEN-004): son las cuentas de [CuentaDeLaVenta], la misma fórmula del saldo —lo devuelto baja lo
  /// que se queda—. Los cobros dados de baja no cuentan (`CobroValido`). Una venta devuelta por
  /// completo no pinta por sí sola (queda en 0). De los deptos de baja ([deBaja]) cuentan solo las
  /// ventas con saldo: las saldadas no pintan nada.
  Future<List<({int montoCentavos, int cobradoCentavos, bool entregada})>> _ventas(
    EspaciosDelColor activos,
    EspaciosDelColor? deBaja,
  ) async {
    final vivas = await _ventasVivasDe(activos);
    final deLosDeBaja = deBaja == null
        ? const <VentaFila>[]
        : await _ventasVivasDe(deBaja, soloVinculosVivos: true);
    final filas = [...vivas, ...deLosDeBaja];
    final idsDeBaja = {for (final f in deLosDeBaja) f.id};
    final devoluciones = await EstadoDeDevolucion.resumenesDe(_db, [for (final f in filas) f.id]);
    final salida = <({int montoCentavos, int cobradoCentavos, bool entregada})>[];
    for (final fila in filas) {
      final cuenta = (devoluciones[fila.id] ?? ResumenDeDevoluciones.ninguna).cuentaDe(
        montoTotalCentavos: fila.montoTotal,
        cobradoCentavos: await CobroValido.cobradoDe(_db, fila.id),
      );
      // Un depto de baja pinta solo por lo que se le debe: saldada o sin nada para cobrar, no.
      if (idsDeBaja.contains(fila.id) && cuenta.seQuedaConCentavos <= cuenta.yaPagoCentavos) {
        continue;
      }
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

  /// Las ventas vivas con plata de [espacios] que se devolvieron por completo, con la fecha de su
  /// última devolución.
  Future<Map<String, DateTime>> _ventasDevueltasPorCompleto(EspaciosDelColor espacios) async {
    final filas = (await _ventasVivasDe(espacios)).where((v) => v.montoTotal > 0).toList();
    final devoluciones = await EstadoDeDevolucion.resumenesDe(_db, [for (final f in filas) f.id]);
    return {
      for (final fila in filas)
        if (devoluciones[fila.id] case final resumen?)
          if (resumen.todoDevuelto && resumen.ultimaFecha != null) fila.id: resumen.ultimaFecha!,
    };
  }
}
