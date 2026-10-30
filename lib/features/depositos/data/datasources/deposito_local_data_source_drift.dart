import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../../mapa/data/datasources/audit_log_table.dart';
import '../../domain/entities/deposito.dart';
import '../models/deposito_model.dart';

/// La persistencia rechazó el depósito: el repositorio la traduce a un `Failure`.
sealed class DepositoRechazadoException implements Exception {
  const DepositoRechazadoException();
}

/// El ticket ya respalda otro depósito vivo (el servidor lo rechazaría con `23505`: un ticket
/// respalda un solo depósito).
final class DepositoTicketYaUsadoException extends DepositoRechazadoException {
  const DepositoTicketYaUsadoException();

  @override
  String toString() => 'DepositoTicketYaUsadoException';
}

/// Lee y escribe los depósitos en la tabla `deposito` de la DB cifrada.
///
/// La escritura es **una transacción de Drift** (contrato-sync-engine §3: [EncoladorSync] se llama
/// adentro, así que si falla se revierte todo): la guarda del ticket, el insert, el encolado y la fila
/// del `audit_log` local.
/// Drift serializa las transacciones, así que dos depósitos seguidos con el mismo ticket nunca
/// entran los dos. Una transacción de otro flujo (por ejemplo, la que guarda el ticket del banco en
/// el mismo paso) puede contener esta: Drift la vuelve un punto de guardado.
final class DepositoLocalDataSourceDrift {
  /// [_encolador] se pasa como `encolador:`.
  DepositoLocalDataSourceDrift(this._db, {required this._encolador});

  final AppDatabase _db;
  final EncoladorSync _encolador;

  /// Ver [DepositoRepository.registrar]. Lanza una [DepositoRechazadoException] si no entra.
  Future<DepositoRegistrado> registrar(Deposito deposito) => _db.transaction(() async {
    final existente = await (_db.select(
      _db.depositos,
    )..where((d) => d.id.equals(deposito.id))).getSingleOrNull();
    if (existente != null) {
      // Un segundo toque o un reintento con el mismo id: no se escribe nada y la respuesta dice lo
      // mismo que la primera.
      return DepositoRegistrado(deposito: _aDeposito(existente), yaEstaba: true);
    }

    final ticketId = deposito.ticketId;
    if (ticketId != null) {
      final otro =
          await (_db.select(_db.depositos)
                ..where((d) => d.ticketId.equals(ticketId) & d.deletedAt.isNull())
                ..limit(1))
              .getSingleOrNull();
      if (otro != null) throw const DepositoTicketYaUsadoException();
    }

    await _db.into(_db.depositos).insert(_aFila(deposito));
    await _encolador.encolar('deposito', OperacionSync.insert, DepositoModel.toJson(deposito));
    // «Audit log local» (HU-CTA-004): una fila por depósito, solo con su id.
    await _db
        .into(_db.auditLogLocal)
        .insert(
          AuditLogLocalCompanion.insert(
            evento: EventoAuditoriaLocal.depositoRegistrado,
            uuid: deposito.id,
            creadoEn: deposito.auditoria.createdAt,
          ),
        );
    return DepositoRegistrado(deposito: deposito);
  });

  /// Ver [DepositoRepository.todos].
  Future<List<Deposito>> todos() async {
    final filas =
        await (_db.select(_db.depositos)
              ..where((d) => d.deletedAt.isNull())
              ..orderBy([(d) => OrderingTerm.desc(d.fecha), (d) => OrderingTerm.desc(d.id)]))
            .get();
    return [for (final fila in filas) _aDeposito(fila)];
  }

  static Deposito _aDeposito(DepositoFila fila) => Deposito(
    id: fila.id,
    montoCentavos: fila.monto,
    fecha: fila.fecha,
    destino: DepositoModel.destinoDesdeCodigo(fila.destino),
    concepto: DepositoModel.conceptoDesdeCodigo(fila.concepto),
    campaniaId: fila.campaniaId,
    ticketId: fila.ticketId,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );

  static DepositosCompanion _aFila(Deposito d) => DepositosCompanion.insert(
    id: d.id,
    monto: d.montoCentavos,
    fecha: d.fecha,
    destino: DepositoModel.codigoDelDestino(d.destino),
    concepto: DepositoModel.codigoDelConcepto(d.concepto),
    campaniaId: Value(d.campaniaId),
    ticketId: Value(d.ticketId),
    createdAt: d.auditoria.createdAt,
    updatedAt: d.auditoria.updatedAt,
    createdBy: Value(d.auditoria.createdBy),
    deletedAt: Value(d.auditoria.deletedAt),
    syncVersion: Value(d.auditoria.syncVersion),
  );
}
