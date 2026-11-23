import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../datos/drift_sync_meta.dart';
import '../../../depositos/data/models/deposito_model.dart';
import '../../domain/entities/alquiler.dart';

/// Arma «Mi alquiler» (HU-CTA-007) con las réplicas locales `campania`, `campania_colportor` y
/// `deposito`: sin red.
///
/// - **Campañas**: las que el colportor tiene con inscripción vigente (sin baja: quien se da de baja
///   deja de deber el alquiler, decisión «Alq. de baja», 27/10) y que cobran alquiler (`alquiler_monto`
///   mayor que 0; sin monto o en 0 la campaña no cobra). Las más nuevas primero.
/// - **Pagos**: los depósitos vivos con concepto `ALQUILER` y esa `campania_id`. Cada uno tiene su
///   estado por las columnas del servidor: un `anulado_at` lo deja «devuelto», un `rechazado_en`
///   «rechazado» (ante la duda no se acredita, como [TotalesDeDepositosDrift]), un `validado_en`
///   «validado» y sin ninguna «por validar».
/// - **Pagado de más**: no queda «a favor»: es lo que bajó la deuda con la casa editora (decisión del
///   28/10, «Alquiler fav»); se calcula por campaña sobre lo validado.
final class AlquilerLocalDataSourceDrift {
  AlquilerLocalDataSourceDrift(this._db);

  final AppDatabase _db;

  Set<ResultSetImplementation<dynamic, dynamic>> get _tablas => {
    _db.campanias,
    _db.campaniasColportor,
    _db.depositos,
    _db.syncMetas,
  };

  /// «Mi alquiler» de ahora, de nuevo cada vez que cambia algo que lo afecta.
  Stream<AlquilerDelColportor> observar(String colportorId) => _db
      .customSelect('SELECT 1 AS cambio_del_alquiler', readsFrom: _tablas)
      .watch()
      .asyncMap((_) => leer(colportorId))
      .distinct();

  /// «Mi alquiler» de ahora.
  Future<AlquilerDelColportor> leer(String colportorId) async {
    final campanias = await _db
        .customSelect(
          'SELECT DISTINCT c.id AS id, c.nombre AS nombre, c.alquiler_monto AS monto, '
          'c.fecha_inicio AS inicio FROM campania c '
          'JOIN campania_colportor cc ON cc.campania_id = c.id '
          'WHERE cc.usuario_id = ? AND cc.deleted_at IS NULL AND c.deleted_at IS NULL '
          'AND c.alquiler_monto > 0 ORDER BY c.fecha_inicio DESC, c.id',
          variables: [Variable<String>(colportorId)],
          readsFrom: _tablas,
        )
        .get();
    final pagos = await _pagosPorCampania();
    return AlquilerDelColportor(
      campanias: [
        for (final f in campanias)
          AlquilerDeCampania(
            campaniaId: f.read<String>('id'),
            campania: f.read<String>('nombre'),
            montoCentavos: f.read<int>('monto'),
            pagos: pagos[f.read<String>('id')] ?? const [],
          ),
      ],
      bajadoEn: (await DriftSyncMeta(_db).read()).lastPullAt,
    );
  }

  /// Los pagos de alquiler de cada campaña, el más nuevo primero.
  Future<Map<String, List<PagoDeAlquiler>>> _pagosPorCampania() async {
    final filas = await _db
        .customSelect(
          'SELECT campania_id, monto, fecha, destino, validado_en, rechazado_en, anulado_at, '
          'motivo_rechazo FROM deposito '
          "WHERE deleted_at IS NULL AND concepto = 'ALQUILER' AND campania_id IS NOT NULL "
          'ORDER BY fecha DESC, id DESC',
          readsFrom: _tablas,
        )
        .get();
    final porCampania = <String, List<PagoDeAlquiler>>{};
    for (final f in filas) {
      final estado = _estado(
        validado: f.readNullable<int>('validado_en') != null,
        rechazado: f.readNullable<int>('rechazado_en') != null,
        anulado: f.readNullable<int>('anulado_at') != null,
      );
      final motivo = f.readNullable<String>('motivo_rechazo')?.trim();
      (porCampania[f.read<String>('campania_id')] ??= []).add(
        PagoDeAlquiler(
          montoCentavos: f.read<int>('monto'),
          fecha: DateTime.fromMillisecondsSinceEpoch(f.read<int>('fecha'), isUtc: true),
          destino: DepositoModel.destinoDesdeCodigo(f.read<String>('destino')),
          estado: estado,
          motivoDelRechazo: estado == EstadoDePagoDeAlquiler.rechazado && (motivo ?? '').isNotEmpty
              ? motivo
              : null,
        ),
      );
    }
    return porCampania;
  }

  /// Anulado y rechazado mandan sobre validado (ante la duda no se acredita).
  static EstadoDePagoDeAlquiler _estado({
    required bool validado,
    required bool rechazado,
    required bool anulado,
  }) {
    if (rechazado) return EstadoDePagoDeAlquiler.rechazado;
    if (anulado) return EstadoDePagoDeAlquiler.devuelto;
    return validado ? EstadoDePagoDeAlquiler.validado : EstadoDePagoDeAlquiler.porValidar;
  }
}
