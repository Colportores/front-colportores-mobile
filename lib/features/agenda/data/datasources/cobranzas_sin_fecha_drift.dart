import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../cobranzas/data/datasources/cobro_valido.dart';
import '../../../ventas/data/datasources/estado_de_devolucion.dart';
import '../../domain/entities/cobranza_por_agendar.dart';

/// Lee de la DB cifrada las ventas del colportor que todavía se deben y no tienen ninguna cobranza
/// agendada (grupo «Sin fecha» de la Agenda, 42B·01G).
///
/// - El saldo es el de siempre ([EstadoDeDevolucion] + [CobroValido]): monto − devuelto − cobrado.
/// - «Agendada» = una cita `COBRANZA` `PROGRAMADA` viva de esa venta (`venta_id`, las cuotas del plan) o,
///   si la cita no dice la venta, de esa persona en esa casa (`espacio_persona_id`), como la agenda
///   «¿Cuándo volvés a cobrar?».
/// - Una venta de una casa o un depto dado de baja no sale: no hay a dónde ir a cobrar.
final class CobranzasSinFechaDrift {
  CobranzasSinFechaDrift(this._db);

  final AppDatabase _db;

  static const _sql =
      'SELECT v.id AS id, v.numero_talonario AS talonario, v.monto_total AS monto, '
      'v.espacio_persona_id AS ep, ep.espacio_id AS espacio, p.nombre AS nombre, '
      'p.apellido AS apellido, u.calle AS calle, u.numero AS numero, COALESCE('
      '(SELECT SUM(c.monto) FROM cobranza c WHERE c.venta_id = v.id AND ${CobroValido.sql}), 0) '
      'AS cobrado '
      'FROM venta v '
      'JOIN espacio_persona ep ON ep.id = v.espacio_persona_id '
      'LEFT JOIN persona p ON p.id = ep.persona_id AND p.deleted_at IS NULL '
      'LEFT JOIN espacio e ON e.id = ep.espacio_id '
      'LEFT JOIN ubicacion u ON u.id = e.ubicacion_id '
      'WHERE v.deleted_at IS NULL AND v.colportor_id = ? '
      'AND e.deleted_at IS NULL AND u.deleted_at IS NULL '
      'AND NOT EXISTS (SELECT 1 FROM agenda a WHERE a.tipo = \'COBRANZA\' '
      'AND a.estado = \'PROGRAMADA\' AND a.deleted_at IS NULL '
      'AND (a.venta_id = v.id OR (a.venta_id IS NULL AND a.espacio_persona_id = v.espacio_persona_id))) '
      'ORDER BY v.fecha, v.id';

  /// Las de [colportorId], de la más vieja a la más nueva; vuelve a emitir cuando cambia una venta, un
  /// cobro, una devolución, una cita o los datos de la persona o la casa.
  Stream<List<CobranzaPorAgendar>> observar(String colportorId) => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          _db.ventas,
          _db.cobranzas,
          _db.devoluciones,
          _db.ventaItems,
          _db.agendas,
          _db.espacioPersonas,
          _db.personas,
          _db.espacios,
          _db.ubicaciones,
        },
      )
      .watch()
      .asyncMap((_) => leer(colportorId));

  /// Una lectura de [observar].
  Future<List<CobranzaPorAgendar>> leer(String colportorId) async {
    final filas = await _db.customSelect(_sql, variables: [Variable<String>(colportorId)]).get();
    final resumenes = await EstadoDeDevolucion.resumenesDe(_db, [
      for (final fila in filas) fila.read<String>('id'),
    ]);
    return [
      for (final fila in filas)
        if ((resumenes[fila.read<String>('id')] ?? ResumenDeDevoluciones.ninguna)
                .cuentaDe(
                  montoTotalCentavos: fila.read<int>('monto'),
                  cobradoCentavos: fila.read<int>('cobrado'),
                )
                .saldoCentavos
            case final saldo when saldo > 0)
          CobranzaPorAgendar(
            ventaId: fila.read<String>('id'),
            numeroTalonario: fila.read<String>('talonario'),
            espacioId: fila.read<String>('espacio'),
            espacioPersonaId: fila.read<String>('ep'),
            saldoCentavos: saldo,
            personaNombre: fila.readNullable<String>('nombre'),
            personaApellido: fila.readNullable<String>('apellido'),
            calle: fila.readNullable<String>('calle'),
            numero: fila.readNullable<String>('numero'),
          ),
    ];
  }
}
