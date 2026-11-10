import 'dart:math' show min;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../../../../core/database/app_database.dart';
import '../../../cobranzas/data/datasources/cobro_valido.dart';
import '../../../ventas/data/datasources/estado_de_entrega.dart';
import '../../domain/entities/ficha_de_persona.dart';
import '../../domain/services/cuenta_de_persona.dart';

/// Lo que la ficha de una persona (HU-UBI-009, vista 32B) lee de sus entregas y sus cobros, y la cuenta
/// (comprado, entregado, pagado, saldo; HU-COB-005): todo de las tablas `venta`, `venta_item`,
/// `entrega` y `cobranza` de la DB cifrada. Nada sale del teléfono.
///
/// - **Qué personas**: las ventas de **todos** los vínculos `espacio_persona` de la persona, también los
///   dados de baja, igual que el historial de la ficha ([FichaPersonaLocalDataSourceDrift]): lo que
///   pasó con ella no se pierde porque ya no esté en ese depto, y la cuenta no puede decir menos que
///   el historial que la acompaña.
/// - **Qué cobros**: los que cuentan para el saldo ([CobroValido]); **qué está entregado**: la misma
///   definición que usa el color de la casa ([EstadoDeEntrega]). Una sola regla, para que ninguna
///   pantalla cuente cosas distintas.
/// - Las ventas, los cobros y las entregas dados de baja no cuentan ni se muestran.
final class CuentaDePersonaLocalDataSourceDrift {
  CuentaDePersonaLocalDataSourceDrift(this._db);

  final AppDatabase _db;

  /// Las ventas vivas de la persona (`?`), por todos sus vínculos.
  static const _ventasDeLaPersona =
      'SELECT v.id FROM venta v WHERE v.deleted_at IS NULL AND v.espacio_persona_id IN '
      '(SELECT ep.id FROM espacio_persona ep WHERE ep.persona_id = ?)';

  DateTime _fecha(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  /// Las entregas hechas y los cobros de [personaId], el más nuevo primero, al día cuando cambia
  /// cualquiera de las tablas que los componen. Un error de lectura sale por el `Stream`.
  Stream<List<MovimientoDeFicha>> observarMovimientos(String personaId) {
    // Drift comparte el stream de dos consultas con el mismo texto y se queda con las tablas de la
    // primera: un `SELECT 1` pelado (el de la ficha) taparía las tablas de acá. El alias lo distingue.
    final cambios = _db.customSelect(
      'SELECT 1 AS movimientos_de_la_persona',
      readsFrom: {
        _db.espacioPersonas,
        _db.ventas,
        _db.ventaItems,
        _db.entregas,
        _db.cobranzas,
        _db.productos,
      },
    );
    return cambios
        .watch()
        .asyncMap((_) => movimientos(personaId))
        .distinct((a, b) => listEquals(a, b));
  }

  /// Ver [observarMovimientos], una sola vez.
  Future<List<MovimientoDeFicha>> movimientos(String personaId) => _db.transaction(() async {
    final salida = <MovimientoDeFicha>[...await _cobros(personaId), ...await _entregas(personaId)]
      ..sort((a, b) {
        final porFecha = b.fecha.compareTo(a.fecha);
        return porFecha != 0 ? porFecha : b.id.compareTo(a.id);
      });
    return List.unmodifiable(salida);
  });

  Future<List<MovimientoDeFicha>> _cobros(String personaId) async {
    final filas = await _db
        .customSelect(
          'SELECT c.id AS id, c.venta_id AS venta_id, c.monto AS monto, c.medio AS medio, c.fecha AS fecha, '
          'v.numero_talonario AS talonario FROM cobranza c JOIN venta v ON v.id = c.venta_id '
          'WHERE ${CobroValido.sql} AND c.venta_id IN ($_ventasDeLaPersona)',
          variables: [Variable<String>(personaId)],
          readsFrom: {_db.cobranzas, _db.ventas, _db.espacioPersonas},
        )
        .get();
    return [
      for (final fila in filas)
        CobroEnFicha(
          id: fila.read<String>('id'),
          fecha: _fecha(fila.read<int>('fecha')),
          montoCentavos: fila.read<int>('monto'),
          efectivo: fila.read<String>('medio') == 'EFECTIVO',
          ventaId: fila.read<String>('venta_id'),
          numeroTalonario: fila.read<String>('talonario'),
        ),
    ];
  }

  /// Las entregas **hechas**, una tarjeta por venta y por momento: al entregar un combo hay una fila
  /// por producto, todas con la misma fecha, y la colportora lo ve como una sola entrega.
  ///
  /// Las **pendientes** no se arman todavía: su fecha prevista (`entrega.fecha_prevista`) la trae la
  /// entrega diferida (HU-VEN-003, #433), y sin ella se mostraría como prevista una fecha inventada.
  Future<List<MovimientoDeFicha>> _entregas(String personaId) async {
    final filas = await _db
        .customSelect(
          'SELECT e.id AS id, e.venta_id AS venta_id, e.cantidad AS cantidad, '
          'COALESCE(e.fecha_entrega, e.created_at) AS fecha, p.nombre AS nombre '
          'FROM entrega e LEFT JOIN producto p ON p.id = e.producto_id '
          'WHERE e.deleted_at IS NULL AND e.pendiente = 0 AND e.venta_id IN ($_ventasDeLaPersona) '
          'ORDER BY e.created_at, e.id',
          variables: [Variable<String>(personaId)],
          readsFrom: {_db.entregas, _db.ventas, _db.espacioPersonas, _db.productos},
        )
        .get();
    final grupos = <(String, int), List<QueryRow>>{};
    for (final fila in filas) {
      (grupos[(fila.read<String>('venta_id'), fila.read<int>('fecha'))] ??= []).add(fila);
    }
    return [
      for (final MapEntry(key: (_, fecha), value: grupo) in grupos.entries)
        EntregaEnFicha(
          id: grupo.first.read<String>('id'),
          fecha: _fecha(fecha),
          pendiente: false,
          lineas: [
            for (final fila in grupo)
              // Un producto que el catálogo ya no trae (la réplica es de solo lectura) queda como
              // «Producto»: no se inventa un nombre.
              LineaDeFicha(
                nombre: fila.readNullable<String>('nombre') ?? 'Producto',
                cantidad: fila.read<int>('cantidad'),
              ),
          ],
        ),
    ];
  }

  /// La cuenta de [personaId]: lo comprado, lo pagado, lo que debe y cuántas de las unidades vendidas
  /// ya se entregaron; `null` si no tiene ventas.
  ///
  /// El saldo es la suma del saldo de cada venta (`monto − cobros válidos`, nunca negativo): una venta
  /// cobrada de más no resta de lo que debe otra (HU-COB-005). Las «entregas» son **unidades**
  /// (decisión del 30/10, gana el canvas: «Entregado 1 de 2» con una venta de dos libros y uno
  /// entregado): lo vendido son las unidades de cada producto (un combo, las de sus componentes) y lo
  /// entregado, las que tienen su fila hecha, sin pasarse de lo vendido de cada producto. Una venta sin
  /// renglones no suma (no hay nada que entregar).
  Future<ResumenCuentaPersona?> resumenDe(String personaId) => _db.transaction(() async {
    final ventas = await _db
        .customSelect(
          'SELECT v.id AS id, v.monto_total AS monto FROM venta v WHERE v.deleted_at IS NULL AND '
          'v.espacio_persona_id IN (SELECT ep.id FROM espacio_persona ep WHERE ep.persona_id = ?)',
          variables: [Variable<String>(personaId)],
          readsFrom: {_db.ventas, _db.espacioPersonas},
        )
        .get();
    if (ventas.isEmpty) return null;

    final cobrados = <String, int>{
      for (final fila
          in await _db
              .customSelect(
                'SELECT c.venta_id AS venta_id, SUM(c.monto) AS cobrado FROM cobranza c '
                'WHERE ${CobroValido.sql} AND c.venta_id IN ($_ventasDeLaPersona) '
                'GROUP BY c.venta_id',
                variables: [Variable<String>(personaId)],
                readsFrom: {_db.cobranzas, _db.ventas, _db.espacioPersonas},
              )
              .get())
        fila.read<String>('venta_id'): fila.read<int>('cobrado'),
    };

    var comprado = 0;
    var pagado = 0;
    var saldo = 0;
    var entregasHechas = 0;
    var entregasTotales = 0;
    for (final venta in ventas) {
      final id = venta.read<String>('id');
      final monto = venta.read<int>('monto');
      final cobrado = cobrados[id] ?? 0;
      comprado += monto;
      pagado += cobrado;
      if (monto > cobrado) saldo += monto - cobrado;

      final vendido = await EstadoDeEntrega.vendidoDe(_db, id);
      if (vendido.isEmpty) continue;
      final entregado = await EstadoDeEntrega.entregadoDe(_db, id);
      for (final MapEntry(:key, :value) in vendido.entries) {
        entregasTotales += value;
        entregasHechas += min(value, entregado[key] ?? 0);
      }
    }
    return ResumenCuentaPersona(
      compradoCentavos: comprado,
      pagadoCentavos: pagado,
      saldoCentavos: saldo,
      entregasHechas: entregasHechas,
      entregasTotales: entregasTotales,
    );
  });
}
