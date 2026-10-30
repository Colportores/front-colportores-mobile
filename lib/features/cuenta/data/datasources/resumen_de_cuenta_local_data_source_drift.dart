import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import '../../../cobranzas/data/datasources/cobro_valido.dart';
import '../../domain/entities/resumen_de_cuenta.dart';

/// Lee de las tablas `venta`, `cobranza` y `devolucion` de la DB cifrada las cifras de Mi Cuenta
/// (HU-CTA-001): lo que el colportor tiene en mano y lo que le deben, con la diferencia contra la
/// semana pasada.
///
/// Todo sale del teléfono y funciona sin conexión. Cada `Stream` emite el valor de ahora al
/// suscribirse y uno nuevo **solo si cambió**, cuando se registra, se da de baja o llega por el pull
/// cualquier venta, cobro o devolución (Drift avisa por tabla).
final class ResumenDeCuentaLocalDataSourceDrift {
  /// [_cobranzas] y [_ahora] se pasan como `cobranzas:` y `ahora:`: un test fija el reloj.
  ResumenDeCuentaLocalDataSourceDrift(this._db, {required this._cobranzas, required this._ahora});

  final AppDatabase _db;
  final CobranzaLocalDataSourceDrift _cobranzas;
  final DateTime Function() _ahora;

  /// Contra cuándo se compara: la semana pasada es «hace 7 días, a esta misma hora».
  static const unaSemana = Duration(days: 7);

  Set<ResultSetImplementation<dynamic, dynamic>> get _tablas => {
    _db.ventas,
    _db.cobranzas,
    _db.devoluciones,
    _db.espacioPersonas,
    _db.espacios,
    _db.ventaItems,
  };

  /// El resumen del colportor [colportorId], de nuevo cada vez que cambia algo que lo afecta.
  Stream<ResumenDeCuenta> observar(String colportorId) => _db
      .customSelect('SELECT 1', readsFrom: _tablas)
      .watch()
      .asyncMap((_) => leer(colportorId))
      .distinct();

  /// El resumen de ahora. El reloj se lee en cada lectura: la ventana de 7 días corre sola.
  Future<ResumenDeCuenta> leer(String colportorId) async {
    final ahora = _ahora();
    final haceUnaSemana = ahora.subtract(unaSemana);
    final hayDatosAnteriores = await _habiaMovimientos(colportorId, haceUnaSemana);
    final enMano = await _enMano(colportorId);
    final porCobrar = await _cobranzas.saldoTotalDe(colportorId);
    return ResumenDeCuenta(
      enMano: CifraDeCuenta(
        totalCentavos: enMano,
        variacionCentavos: hayDatosAnteriores
            ? enMano - await _enMano(colportorId, hasta: haceUnaSemana)
            : null,
      ),
      porCobrar: CifraDeCuenta(
        totalCentavos: porCobrar,
        variacionCentavos: hayDatosAnteriores
            ? porCobrar - await _cobranzas.saldoTotalHasta(colportorId, haceUnaSemana)
            : null,
      ),
    );
  }

  /// El colportor ya tenía alguna venta (viva o dada de baja) hasta [hasta]: sin ninguna, no hay con
  /// qué comparar y la diferencia no se inventa (33A-04, «Sin datos de la semana anterior»).
  Future<bool> _habiaMovimientos(String colportorId, DateTime hasta) async {
    final fila = await _db
        .customSelect(
          'SELECT 1 AS hay FROM venta v WHERE v.colportor_id = ? AND v.fecha <= ? LIMIT 1',
          variables: [
            Variable<String>(colportorId),
            Variable<int>(hasta.toUtc().millisecondsSinceEpoch),
          ],
        )
        .getSingleOrNull();
    return fila != null;
  }

  /// El efectivo cobrado que todavía no se depositó: los cobros en efectivo vivos de las ventas del
  /// colportor menos lo que reembolsó a los clientes en el momento al devolver (decisión del 30/10
  /// en #431), nunca negativo. Con [hasta], como estaba entonces.
  ///
  /// Una venta dada de baja no resta: el efectivo que se cobró sigue en la mano. Hasta que el
  /// depósito (HU-CTA-004, #442) exista en el teléfono no hay nada que depositar: cuando llegue, lo
  /// depositado se resta acá.
  Future<int> _enMano(String colportorId, {DateTime? hasta}) async {
    final ms = hasta?.toUtc().millisecondsSinceEpoch;
    final cobrado = await _suma(
      'SELECT COALESCE(SUM(c.monto), 0) AS suma FROM cobranza c '
      'JOIN venta v ON v.id = c.venta_id '
      "WHERE v.colportor_id = ? AND c.medio = 'EFECTIVO' AND ${CobroValido.sql}"
      '${ms == null ? '' : ' AND c.fecha <= ?'}',
      colportorId,
      ms,
    );
    final reembolsado = await _suma(
      'SELECT COALESCE(SUM(d.monto_reembolsado), 0) AS suma FROM devolucion d '
      'JOIN venta v ON v.id = d.venta_id '
      'WHERE v.colportor_id = ? AND d.deleted_at IS NULL'
      '${ms == null ? '' : ' AND d.fecha_devolucion <= ?'}',
      colportorId,
      ms,
    );
    final enMano = cobrado - reembolsado;
    return enMano < 0 ? 0 : enMano;
  }

  Future<int> _suma(String sql, String colportorId, int? ms) async {
    final fila = await _db
        .customSelect(
          sql,
          variables: [Variable<String>(colportorId), if (ms != null) Variable<int>(ms)],
        )
        .getSingle();
    return fila.read<int>('suma');
  }
}
