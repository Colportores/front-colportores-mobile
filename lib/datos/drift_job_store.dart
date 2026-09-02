// `sync_queue` sobre Drift: la cola de jobs del motor, persistida.
//
// Hasta acá el prototipo corría sobre `InMemoryJobStore`, o sea que al cerrar la
// app se perdía todo lo que estaba esperando subir. Una venta hecha sin señal y
// la app cerrada antes de recuperar conexión: la venta no existía más.
//
// El motor se verificó entero contra el fake, así que lo único que garantiza
// que esto se comporte igual es `runJobStoreContract` — la definición ejecutable
// del puerto, que corre en `test/drift_stores_test.dart`.

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sync_engine/sync_engine.dart';

import 'db.dart';

class DriftJobStore implements JobStorePort {
  DriftJobStore(this._db, {UuidV7? uuid, DateTime Function()? clock})
      : _uuid = uuid ?? UuidV7(),
        _clock = clock ?? (() => DateTime.now().toUtc());

  final DbLocal _db;
  final UuidV7 _uuid;
  final DateTime Function() _clock;

  static const _pending = 'PENDING';
  static const _inFlight = 'IN_FLIGHT';
  static const _invalid = 'INVALID';
  static const _done = 'DONE';

  @override
  Future<String> append(SyncJob job) async {
    final id = _uuid.next();
    await _db.into(_db.syncQueue).insert(SyncQueueCompanion.insert(
          id: id,
          clientOpId: job.clientOpId,
          entity: job.entity,
          op: job.op.name,
          payload: jsonEncode(job.payload),
          syncVersion: Value(job.syncVersion),
          createdAt: job.createdAt,
          state: _pending,
        ));
    return id;
  }

  @override
  Future<List<QueuedJob>> claimPending({int limit = 100}) =>
      // Seleccionar y marcar tienen que ser indivisibles: si dos ciclos se
      // pisan entre el SELECT y el UPDATE, los dos se llevan el mismo job y la
      // misma venta sale dos veces. El `client_op_id` la deduplicaría del lado
      // del servidor, pero gastando el viaje y ensuciando la cola.
      _db.transaction(() async {
        final filas = await (_db.select(_db.syncQueue)
              ..where((t) => t.state.equals(_pending))
              // §5.5: orden de creación, no de inserción. El desempate por id
              // es lo que hace la salida determinista cuando dos jobs comparten
              // el instante — sin él, un update podría adelantarse a su insert.
              ..orderBy([
                (t) => OrderingTerm(expression: t.createdAt),
                (t) => OrderingTerm(expression: t.id),
              ])
              ..limit(limit))
            .get();
        if (filas.isEmpty) return const <QueuedJob>[];

        await (_db.update(_db.syncQueue)
              ..where((t) => t.id.isIn(filas.map((f) => f.id))))
            .write(SyncQueueCompanion(
          state: const Value(_inFlight),
          claimedAt: Value(_clock()),
        ));

        return [for (final f in filas) _aQueuedJob(f, estado: JobState.inFlight)];
      });

  @override
  Future<void> markDone(Iterable<String> jobIds, {required DateTime at}) async {
    if (jobIds.isEmpty) return;
    await (_db.update(_db.syncQueue)..where((t) => t.id.isIn(jobIds))).write(
      SyncQueueCompanion(state: const Value(_done), doneAt: Value(at)),
    );
  }

  @override
  Future<void> markInvalid(String jobId,
      {required String code, String message = ''}) async {
    await (_db.update(_db.syncQueue)..where((t) => t.id.equals(jobId))).write(
      SyncQueueCompanion(
        state: const Value(_invalid),
        code: Value(code),
        message: Value(message),
      ),
    );
  }

  @override
  Future<void> markPending(Iterable<String> jobIds) async {
    if (jobIds.isEmpty) return;
    await (_db.update(_db.syncQueue)..where((t) => t.id.isIn(jobIds))).write(
      // El claim se limpia al soltarlo: si quedara pegado, el próximo reclamo
      // lo mediría contra un instante que ya no significa nada.
      const SyncQueueCompanion(
          state: Value(_pending), claimedAt: Value(null)),
    );
  }

  @override
  Future<void> requeue(String jobId) async {
    // El código y el mensaje se limpian: el error viejo no puede quedar pegado
    // a un job que el colportor ya corrigió, o la cola de error muestra para
    // siempre un motivo que dejó de ser cierto.
    await (_db.update(_db.syncQueue)..where((t) => t.id.equals(jobId))).write(
      const SyncQueueCompanion(
        state: Value(_pending),
        code: Value(''),
        message: Value(''),
      ),
    );
  }

  @override
  Future<int> discardInvalid(Iterable<String> jobIds) async {
    if (jobIds.isEmpty) return 0;
    // El `state == INVALID` del where no es decorativo: es lo que hace que
    // borrar sea seguro contra el isolate de segundo plano. Los dos motores
    // comparten esta base, y sin esa condición un descarte disparado desde la
    // pantalla podría llevarse un job que el ciclo de fondo acaba de pasar a
    // IN_FLIGHT y está mandando en ese momento.
    return (_db.delete(_db.syncQueue)
          ..where((t) => t.id.isIn(jobIds) & t.state.equals(_invalid)))
        .go();
  }

  @override
  Future<int> reclaimInFlight(Duration staleAfter) async {
    // Un job queda IN_FLIGHT mientras un ciclo lo tiene en la mano. Si el
    // proceso muere ahí —Android matando la app, batería—, nadie lo reclama:
    // `claimPending` no lo mira y la venta no sube nunca. Reenviarlo es seguro:
    // el `client_op_id` hace que el servidor conteste `duplicate` (§5.3).
    //
    // Pero solo lo **vencido**: el ciclo de segundo plano corre en otro isolate
    // sobre esta misma base, y reclamar todo se llevaría puestos los jobs que
    // el primer plano está mandando en ese momento.
    final corte = _clock().subtract(staleAfter);
    return (_db.update(_db.syncQueue)
          ..where((t) =>
              t.state.equals(_inFlight) &
              // `claimed_at` null es una fila anterior a la migración a v2:
              // no hay instante contra el cual medirla, y dejarla colgada para
              // siempre sería perder esa venta.
              (t.claimedAt.isNull() |
                  t.claimedAt.isSmallerOrEqualValue(corte))))
        .write(const SyncQueueCompanion(
            state: Value(_pending), claimedAt: Value(null)));
  }

  @override
  Future<SyncStatus> status() async {
    final cuenta = _db.syncQueue.id.count();
    final q = _db.selectOnly(_db.syncQueue)
      ..addColumns([_db.syncQueue.state, cuenta])
      ..groupBy([_db.syncQueue.state]);

    final porEstado = {
      for (final f in await q.get())
        f.read(_db.syncQueue.state)!: f.read(cuenta) ?? 0,
    };
    return SyncStatus(
      pending: porEstado[_pending] ?? 0,
      inFlight: porEstado[_inFlight] ?? 0,
      invalid: porEstado[_invalid] ?? 0,
    );
  }

  @override
  Future<List<QueuedJob>> listInvalid({int limit = 100}) async {
    final filas = await (_db.select(_db.syncQueue)
          ..where((t) => t.state.equals(_invalid))
          // Del más reciente al más viejo: lo que el colportor acaba de romper
          // es lo que necesita ver primero.
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.createdAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
    return [for (final f in filas) _aQueuedJob(f, estado: JobState.invalid)];
  }

  @override
  Future<int> purgeDone(DateTime before) => (_db.delete(_db.syncQueue)
        ..where((t) => t.state.equals(_done) & t.doneAt.isSmallerThanValue(before)))
      .go();

  QueuedJob _aQueuedJob(FilaDeCola f, {required JobState estado}) => QueuedJob(
        id: f.id,
        state: estado,
        code: f.code,
        message: f.message,
        doneAt: f.doneAt,
        claimedAt: f.claimedAt,
        job: SyncJob(
          clientOpId: f.clientOpId,
          entity: f.entity,
          op: Op.values.byName(f.op),
          payload: (jsonDecode(f.payload) as Map).cast<String, Object?>(),
          syncVersion: f.syncVersion,
          createdAt: f.createdAt,
        ),
      );
}
