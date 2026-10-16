import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sync_engine/sync_engine.dart';

import '../core/database/app_database.dart';
import 'sync_queue_table.dart';

part 'drift_job_store.g.dart';

/// [JobStorePort] sobre `sync_queue` ([SyncQueue]): la cola del motor, persistida y cifrada.
///
/// Sin esto el motor corre sobre la cola en memoria: al cerrar la app se pierde todo lo que
/// esperaba subir. Lo único que garantiza que se porte como `InMemoryJobStore` —contra el que se
/// verificó el motor entero— es `runJobStoreContract`, que corre en
/// `test/unit/datos/drift_job_store_test.dart`.
///
/// Es un DAO del [AppDatabase] que abrió `DatabaseHelper`: `append` se llama **dentro de la
/// transacción** en la que la app escribe la fila de negocio (contrato §3), y por ser la misma
/// conexión entra en ella. O se guardan las dos cosas o ninguna.
@DriftAccessor(tables: [SyncQueue])
final class DriftJobStore extends DatabaseAccessor<AppDatabase>
    with _$DriftJobStoreMixin
    implements JobStorePort {
  DriftJobStore(super.attachedDatabase, {UuidV7? uuid, DateTime Function()? clock})
    : _uuid = uuid ?? UuidV7(),
      _clock = clock ?? (() => DateTime.now().toUtc());

  final UuidV7 _uuid;
  final DateTime Function() _clock;

  static const _estados = {
    EstadoJob.pending: JobState.pending,
    EstadoJob.inFlight: JobState.inFlight,
    EstadoJob.invalid: JobState.invalid,
    EstadoJob.done: JobState.done,
    EstadoJob.blocked: JobState.blocked,
    EstadoJob.waiting: JobState.waiting,
  };

  @override
  Future<String> append(SyncJob job) async {
    // UUID v7 monótono: dos jobs del mismo milisegundo desempatan por id en el orden en que
    // llegaron (§5.5).
    final id = _uuid.next();
    await into(syncQueue).insert(
      SyncQueueCompanion.insert(
        id: id,
        clientOpId: job.clientOpId,
        entity: job.entity,
        op: job.op.name,
        payload: jsonEncode(job.payload),
        syncVersion: Value(job.syncVersion),
        rowPk: Value(job.rowPk),
        createdAt: job.createdAt,
        state: EstadoJob.pending,
      ),
    );
    return id;
  }

  @override
  Future<List<QueuedJob>> claimPending({int limit = 500}) => transaction(() async {
    // Seleccionar y marcar van juntos: si dos ciclos se cruzan entre el SELECT y el UPDATE, los
    // dos se llevan el mismo job. El `client_op_id` lo deduplica en el servidor (§5.3), pero
    // gastando el viaje que RR-07 cuida.
    final filas =
        await (_enOrden(select(syncQueue))
              ..where((q) => q.state.equals(EstadoJob.pending))
              ..limit(limit))
            .get();
    if (filas.isEmpty) return const [];
    final ahora = _clock();
    await (update(syncQueue)..where((q) => q.id.isIn([for (final f in filas) f.id]))).write(
      SyncQueueCompanion(state: const Value(EstadoJob.inFlight), claimedAt: Value(ahora)),
    );
    return [
      for (final f in filas) _aJob(f.copyWith(state: EstadoJob.inFlight, claimedAt: Value(ahora))),
    ];
  });

  @override
  Future<void> markDone(Iterable<String> jobIds, {required DateTime at}) =>
      (update(syncQueue)..where((q) => q.id.isIn(jobIds))).write(
        SyncQueueCompanion(
          state: const Value(EstadoJob.done),
          doneAt: Value(at),
          claimedAt: const Value(null),
        ),
      );

  @override
  Future<void> markInvalid(String jobId, {required String code, String message = ''}) =>
      _conMotivo(jobId, EstadoJob.invalid, code: code, message: message);

  @override
  Future<void> markBlocked(String jobId, {required String code, String message = ''}) =>
      _conMotivo(jobId, EstadoJob.blocked, code: code, message: message);

  @override
  Future<void> markWaiting(
    String jobId, {
    required String dependsOn,
    String code = '',
    String message = '',
  }) => _conMotivo(jobId, EstadoJob.waiting, code: code, message: message, dependsOn: dependsOn);

  Future<void> _conMotivo(
    String jobId,
    String estado, {
    required String code,
    required String message,
    String? dependsOn,
  }) => (update(syncQueue)..where((q) => q.id.equals(jobId))).write(
    SyncQueueCompanion(
      state: Value(estado),
      code: Value(code),
      message: Value(message),
      dependsOn: Value(dependsOn),
      claimedAt: const Value(null),
    ),
  );

  @override
  Future<void> markPending(Iterable<String> jobIds) =>
      (update(syncQueue)..where((q) => q.id.isIn(jobIds))).write(
        const SyncQueueCompanion(state: Value(EstadoJob.pending), claimedAt: Value(null)),
      );

  @override
  Future<void> requeue(String jobId) =>
      (update(
        syncQueue,
      )..where((q) => q.id.equals(jobId) & q.state.equals(EstadoJob.invalid))).write(
        const SyncQueueCompanion(
          state: Value(EstadoJob.pending),
          code: Value(''),
          message: Value(''),
        ),
      );

  @override
  Future<List<QueuedJob>> listHeld() async {
    final filas = await (_enOrden(
      select(syncQueue),
    )..where((q) => q.state.isIn([EstadoJob.blocked, EstadoJob.waiting]))).get();
    return filas.map(_aJob).toList();
  }

  @override
  Future<void> replacePayload(String jobId, Map<String, Object?> payload) async {
    final cambiadas =
        await (update(syncQueue)
              ..where((q) => q.id.equals(jobId) & q.state.isIn(EstadoJob.sinMandar)))
            .write(SyncQueueCompanion(payload: Value(jsonEncode(payload))));
    if (cambiadas == 0) throw StateError('replacePayload sobre un job que ya salió: $jobId');
  }

  @override
  Future<List<QueuedJob>> unsentFor(String entity, String rowPk) async {
    final filas =
        await (_enOrden(select(syncQueue))..where(
              (q) =>
                  q.entity.equals(entity) &
                  q.rowPk.equals(rowPk) &
                  q.state.isIn(EstadoJob.sinMandar),
            ))
            .get();
    return filas.map(_aJob).toList();
  }

  @override
  Future<void> rebaseVersions(String entity, Map<String, int> versionPorFila) =>
      transaction(() async {
        for (final MapEntry(key: pk, value: version) in versionPorFila.entries) {
          await (update(syncQueue)..where(
                (q) =>
                    q.entity.equals(entity) &
                    q.rowPk.equals(pk) &
                    q.op.equals(Op.insert.name).not() &
                    q.state.isIn(EstadoJob.sinAplicar),
              ))
              .write(SyncQueueCompanion(syncVersion: Value(version)));
        }
      });

  @override
  Future<void> release(List<String> jobIds, {required DateTime at}) => transaction(() async {
    // Detrás de todo: un milisegundo después del último de la cola, o de [at] si es más tarde, y
    // uno más por cada job, para que el orden de [jobIds] sea el del claim.
    final ultimo = syncQueue.createdAt.max();
    final maximo = await (selectOnly(
      syncQueue,
    )..addColumns([ultimo])).map((f) => f.read(ultimo)).getSingle();
    var base = at.millisecondsSinceEpoch;
    if (maximo != null && maximo >= base) base = maximo + 1;
    for (final (i, id) in jobIds.indexed) {
      await (update(syncQueue)
            ..where((q) => q.id.equals(id) & q.state.isIn([EstadoJob.blocked, EstadoJob.waiting])))
          .write(
            SyncQueueCompanion(
              state: const Value(EstadoJob.pending),
              code: const Value(''),
              message: const Value(''),
              dependsOn: const Value(null),
              createdAt: Value(DateTime.fromMillisecondsSinceEpoch(base + i, isUtc: true)),
            ),
          );
    }
  });

  @override
  Future<int> discardHeld(Iterable<String> jobIds) => (delete(
    syncQueue,
  )..where((q) => q.id.isIn(jobIds) & q.state.isIn([EstadoJob.blocked, EstadoJob.waiting]))).go();

  @override
  Future<int> discardInvalid(Iterable<String> jobIds) =>
      (delete(syncQueue)..where((q) => q.id.isIn(jobIds) & q.state.equals(EstadoJob.invalid))).go();

  @override
  Future<int> reclaimInFlight(Duration staleAfter) {
    final corte = _clock().subtract(staleAfter);
    // Un `IN_FLIGHT` sin `claimed_at` no tiene cómo probar que alguien lo tiene: se reclama.
    return (update(syncQueue)..where(
          (q) =>
              q.state.equals(EstadoJob.inFlight) &
              (q.claimedAt.isNull() |
                  q.claimedAt.isSmallerOrEqualValue(corte.millisecondsSinceEpoch)),
        ))
        .write(const SyncQueueCompanion(state: Value(EstadoJob.pending), claimedAt: Value(null)));
  }

  @override
  Future<SyncStatus> status() async {
    final cantidad = syncQueue.id.count();
    final filas =
        await (selectOnly(syncQueue)
              ..addColumns([syncQueue.state, cantidad])
              ..groupBy([syncQueue.state]))
            .get();
    final por = {for (final f in filas) f.read(syncQueue.state)!: f.read(cantidad) ?? 0};
    return SyncStatus(
      pending: por[EstadoJob.pending] ?? 0,
      inFlight: por[EstadoJob.inFlight] ?? 0,
      invalid: por[EstadoJob.invalid] ?? 0,
      blocked: por[EstadoJob.blocked] ?? 0,
      waiting: por[EstadoJob.waiting] ?? 0,
    );
  }

  @override
  Future<List<QueuedJob>> listInvalid({int limit = 100}) async {
    final filas =
        await (select(syncQueue)
              ..where((q) => q.state.equals(EstadoJob.invalid))
              ..orderBy([(q) => OrderingTerm.desc(q.createdAt), (q) => OrderingTerm.desc(q.id)])
              ..limit(limit))
            .get();
    return filas.map(_aJob).toList();
  }

  @override
  Future<int> purgeDone(DateTime before) =>
      (delete(syncQueue)..where(
            (q) =>
                q.state.equals(EstadoJob.done) &
                q.doneAt.isSmallerThanValue(before.millisecondsSinceEpoch),
          ))
          .go();

  /// §5.5: orden de creación, y el id (UUID v7) desempata los del mismo milisegundo.
  SimpleSelectStatement<$SyncQueueTable, SyncQueueFila> _enOrden(
    SimpleSelectStatement<$SyncQueueTable, SyncQueueFila> consulta,
  ) => consulta..orderBy([(q) => OrderingTerm.asc(q.createdAt), (q) => OrderingTerm.asc(q.id)]);

  QueuedJob _aJob(SyncQueueFila f) => QueuedJob(
    id: f.id,
    state: _estados[f.state]!,
    code: f.code,
    message: f.message,
    doneAt: f.doneAt,
    claimedAt: f.claimedAt,
    dependsOn: f.dependsOn,
    job: SyncJob(
      clientOpId: f.clientOpId,
      entity: f.entity,
      op: Op.values.byName(f.op),
      payload: (jsonDecode(f.payload) as Map<String, Object?>),
      syncVersion: f.syncVersion,
      createdAt: f.createdAt,
      rowPk: f.rowPk,
    ),
  );
}
