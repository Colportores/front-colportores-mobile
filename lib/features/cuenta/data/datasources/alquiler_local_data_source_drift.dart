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
///   estado por las columnas del servidor: un `anulado_at` lo deja «devuelto», un `rechazado_en` (o,
///   sin validar, su ticket `RECHAZADO`: el depósito de banco u oficina se rechaza con su ticket)
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
    _db.tickets,
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
    // El depósito de banco u oficina se rechaza con su ticket (`ticket.estado = 'RECHAZADO'`), no con
    // `rechazado_en` (esa marca es del retiro, 0152): sin el ticket quedaría «por validar» para siempre.
    final filas = await _db
        .customSelect(
          'SELECT d.campania_id AS campania_id, d.monto AS monto, d.fecha AS fecha, '
          'd.destino AS destino, d.validado_en AS validado_en, d.rechazado_en AS rechazado_en, '
          'd.anulado_at AS anulado_at, d.motivo_rechazo AS motivo_rechazo, '
          't.estado AS ticket_estado, t.motivo_rechazo AS ticket_motivo FROM deposito d '
          'LEFT JOIN ticket t ON t.id = d.ticket_id AND t.deleted_at IS NULL '
          "WHERE d.deleted_at IS NULL AND d.concepto = 'ALQUILER' AND d.campania_id IS NOT NULL "
          'ORDER BY d.fecha DESC, d.id DESC',
          readsFrom: _tablas,
        )
        .get();
    final porCampania = <String, List<PagoDeAlquiler>>{};
    for (final f in filas) {
      final validado = f.readNullable<int>('validado_en') != null;
      final ticketRechazado = !validado && f.readNullable<String>('ticket_estado') == 'RECHAZADO';
      final estado = _estado(
        validado: validado,
        rechazado: f.readNullable<int>('rechazado_en') != null || ticketRechazado,
        anulado: f.readNullable<int>('anulado_at') != null,
      );
      final motivo =
          (ticketRechazado
                  ? f.readNullable<String>('ticket_motivo')
                  : f.readNullable<String>('motivo_rechazo'))
              ?.trim();
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
