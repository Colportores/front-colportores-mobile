import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../datos/drift_sync_meta.dart';
import '../../../depositos/data/models/deposito_model.dart';
import '../../domain/entities/alquiler.dart';

/// Arma «Mi alquiler» (HU-CTA-007) con las réplicas locales `campania`, `campania_colportor`, `deposito` y
/// `alquiler_decision`: sin red.
///
/// - **Campañas**: las que el colportor tiene con inscripción vigente (sin baja: quien se da de baja
///   deja de deber el alquiler, decisión «Alq. de baja», 27/10) y que cobran alquiler (`alquiler_monto`
///   mayor que 0; sin monto o en 0 la campaña no cobra). Las más nuevas primero.
/// - **Pagos**: los depósitos vivos con concepto `ALQUILER` y esa `campania_id`. Cada uno tiene su
///   estado por las columnas del servidor: un `anulado_at` lo deja «devuelto», un `rechazado_en` (o,
///   sin validar, su ticket `RECHAZADO`: el depósito de banco u oficina se rechaza con su ticket)
///   «rechazado» (ante la duda no se acredita, como [TotalesDeDepositosDrift]), un `validado_en`
///   «validado» y sin ninguna «por validar».
/// - **Campañas de la baja** (#740): las que tienen su inscripción con `deleted_at` y ninguna vigente
///   (si volvió, es una campaña como cualquiera) y donde hay algo que decir: un pago de alquiler o una
///   decisión vigente del coordinador. No tienen saldo (quien se da de baja deja de deber el alquiler) ni
///   importa si la campaña cobraba: lo pagado lo decide el coordinador. Las decisiones deshechas
///   (`deleted_at`) no cuentan.
/// - **Pagado de más**: no queda «a favor»: es lo que bajó la deuda con la casa editora (decisión del
///   28/10, «Alquiler fav»). Lo dice el servidor (`cuenta_colportor.alquiler_trasladado`, 0152, el total
///   de todas las campañas): el teléfono no lo calcula.
final class AlquilerLocalDataSourceDrift {
  AlquilerLocalDataSourceDrift(this._db);

  final AppDatabase _db;

  Set<ResultSetImplementation<dynamic, dynamic>> get _tablas => {
    _db.campanias,
    _db.campaniasColportor,
    _db.cuentasColportor,
    _db.depositos,
    _db.alquilerDecisiones,
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
      bajas: await _bajas(colportorId, pagos),
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
      trasladadoCentavos: await _trasladado(colportorId),
    );
  }

  /// Lo pagado de más que el servidor pasó a la deuda con la casa editora: `alquiler_trasladado` de la
  /// cuenta de [colportorId]. Sin cuenta bajada, o dada de baja, no hay traslado (0); nunca negativo.
  Future<int> _trasladado(String colportorId) async {
    final cuenta = await (_db.select(
      _db.cuentasColportor,
    )..where((c) => c.usuarioId.equals(colportorId) & c.deletedAt.isNull())).getSingleOrNull();
    final centavos = cuenta?.alquilerTrasladado ?? 0;
    return centavos > 0 ? centavos : 0;
  }

  /// Las campañas de las que se dio de baja con algo que decir, la más nueva primero.
  Future<List<AlquilerDeBaja>> _bajas(
    String colportorId,
    Map<String, List<PagoDeAlquiler>> pagos,
  ) async {
    final campanias = await _db
        .customSelect(
          'SELECT c.id AS id, c.nombre AS nombre FROM campania c WHERE c.deleted_at IS NULL '
          'AND EXISTS (SELECT 1 FROM campania_colportor b WHERE b.campania_id = c.id '
          'AND b.usuario_id = ? AND b.deleted_at IS NOT NULL) '
          'AND NOT EXISTS (SELECT 1 FROM campania_colportor v WHERE v.campania_id = c.id '
          'AND v.usuario_id = ? AND v.deleted_at IS NULL) '
          'ORDER BY c.fecha_inicio DESC, c.id',
          variables: [Variable<String>(colportorId), Variable<String>(colportorId)],
          readsFrom: _tablas,
        )
        .get();
    if (campanias.isEmpty) return const [];
    final decisiones = await _decisionesPorCampania(colportorId);
    return [
      for (final f in campanias)
        if ((pagos[f.read<String>('id')] ?? const []).isNotEmpty ||
            (decisiones[f.read<String>('id')] ?? const []).isNotEmpty)
          AlquilerDeBaja(
            campaniaId: f.read<String>('id'),
            campania: f.read<String>('nombre'),
            pagos: pagos[f.read<String>('id')] ?? const [],
            decisiones: decisiones[f.read<String>('id')] ?? const [],
          ),
    ];
  }

  /// Las decisiones vigentes del coordinador de cada campaña, la más nueva primero. Una con un destino
  /// que esta versión de la app no conoce se ignora: no se inventa lo que nadie decidió.
  Future<Map<String, List<DecisionDeAlquiler>>> _decisionesPorCampania(String colportorId) async {
    final filas = await _db
        .customSelect(
          'SELECT campania_id, decision, monto, created_at FROM alquiler_decision '
          'WHERE usuario_id = ? AND deleted_at IS NULL ORDER BY created_at DESC, id DESC',
          variables: [Variable<String>(colportorId)],
          readsFrom: _tablas,
        )
        .get();
    final porCampania = <String, List<DecisionDeAlquiler>>{};
    for (final f in filas) {
      final destino = DestinoDeLoPagado.desdeCodigo(f.read<String>('decision'));
      if (destino == null) continue;
      (porCampania[f.read<String>('campania_id')] ??= []).add(
        DecisionDeAlquiler(
          destino: destino,
          montoCentavos: f.read<int>('monto'),
          decididaEn: DateTime.fromMillisecondsSinceEpoch(f.read<int>('created_at'), isUtc: true),
        ),
      );
    }
    return porCampania;
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
