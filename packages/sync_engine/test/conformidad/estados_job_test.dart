// Suite de conformidad (§8) — la máquina de estados de §5.1.
//
//   "Un job con 422 del backend termina en INVALID y no se reintenta; uno con
//    timeout termina en PENDING y se reintenta al trigger siguiente."

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

const _entidades = {'venta', 'producto', 'persona'};

SpecRegistry _registro() => SpecRegistry([
      SyncSpec.push('venta', critical: false),
      SyncSpec.pull('producto'),
      SyncSpec.local('persona'),
    ], allEntities: _entidades);

({SyncEngine motor, InMemoryJobStore jobs, FakeSyncTransport transport})
    _armar() {
  final jobs = InMemoryJobStore();
  final transport = FakeSyncTransport();
  return (
    motor: SyncEngine(
      specs: _registro(),
      transport: transport,
      jobs: jobs,
      store: InMemoryLocalStore(),
    ),
    jobs: jobs,
    transport: transport,
  );
}

Future<String> _stage(SyncEngine motor, String pk, {String? opId}) =>
    motor.stage('venta', Op.insert, {'id': pk, 'total': '1200.00'},
        clientOpId: opId ?? 'op-$pk');

void main() {
  test('un 422 termina en INVALID y no se reintenta solo', () async {
    final (:motor, :jobs, :transport) = _armar();
    final id = await _stage(motor, 'v1');

    transport.failWith(422, code: 'VENTA_SIN_ITEMS');
    await motor.syncNow();

    expect(jobs.byId(id).state, JobState.invalid);
    expect(jobs.byId(id).code, 'VENTA_SIN_ITEMS');

    // El trigger siguiente no lo toca: los INVALID no vuelven solos.
    await motor.syncNow();
    expect(jobs.byId(id).state, JobState.invalid);
    expect(transport.appliedOpIds, isEmpty);

    // Solo requeue() lo devuelve a la cola, y ahí sí sube (§3).
    await motor.requeue(id);
    expect(jobs.byId(id).state, JobState.pending);
    await motor.syncNow();
    expect(jobs.byId(id).state, JobState.done);

    await motor.dispose();
  });

  test('un timeout deja el job en PENDING y sube al trigger siguiente',
      () async {
    final (:motor, :jobs, :transport) = _armar();
    final id = await _stage(motor, 'v1');

    transport.failTransient();
    final primero = await motor.syncNow();

    expect(primero.ok, isFalse);
    expect(primero.failure!.kind, FailureKind.transient);
    expect(jobs.byId(id).state, JobState.pending,
        reason: 'sin retry counter: vuelve a la cola tal cual');

    final segundo = await motor.trigger(SyncTrigger.connectivity);
    expect(segundo.ok, isTrue);
    expect(jobs.byId(id).state, JobState.done);

    await motor.dispose();
  });

  test('una racha larga de fallas no agota nada: el job sigue PENDING',
      () async {
    final (:motor, :jobs, :transport) = _armar();
    final id = await _stage(motor, 'v1');

    transport.offline();
    for (var i = 0; i < 20; i++) {
      await motor.trigger(SyncTrigger.appResumed);
    }
    expect(jobs.byId(id).state, JobState.pending);

    transport.online();
    await motor.syncNow();
    expect(jobs.byId(id).state, JobState.done);
    expect(transport.rowsOf('venta'), hasLength(1),
        reason: '21 intentos, una sola venta');

    await motor.dispose();
  });

  test('un job inválido no arrastra a los demás del lote', () async {
    final (:motor, :jobs, :transport) = _armar();
    final bueno = await _stage(motor, 'v1', opId: 'op-bueno');
    final malo = await _stage(motor, 'v2', opId: 'op-malo');

    transport.rejectJob('op-malo', 'PRODUCTO_INEXISTENTE');
    await motor.syncNow();

    expect(jobs.byId(bueno).state, JobState.done);
    expect(jobs.byId(malo).state, JobState.invalid);

    await motor.dispose();
  });

  test('un conflicto se resuelve por LWW y no va a la cola de error', () async {
    final jobs = InMemoryJobStore();
    final store = InMemoryLocalStore();
    final transport = FakeSyncTransport();
    final motor = SyncEngine(
        specs: _registro(), transport: transport, jobs: jobs, store: store);

    await _stage(motor, 'v1', opId: 'op-1');
    await motor.syncNow();

    // Otro dispositivo la movió a la versión 2 mientras tanto.
    await transport.push(PushBatch([
      SyncJob(
        clientOpId: 'op-otro-celu',
        entity: 'venta',
        op: Op.update,
        payload: {'id': 'v1', 'total': '9999.00'},
        syncVersion: 1,
        createdAt: DateTime.utc(2026, 8, 28),
      )
    ]));

    final id = await motor.stage(
        'venta', Op.update, {'id': 'v1', 'total': '1300.00'},
        clientOpId: 'op-tarde', syncVersion: 1);
    await motor.syncNow();

    expect(jobs.byId(id).state, JobState.done,
        reason: 'un 409 no es culpa del colportor: no va a INVALID');
    expect(store.rows['venta']!.last['total'], '9999.00',
        reason: 'el servidor gana por sync_version (§5.4)');

    await motor.dispose();
  });
}
