// Dos cosas al mismo tiempo.
//
// El colportor toca "hacer backup" mientras corre el del cierre de jornada. O
// vuelve la red justo mientras el wizard de recuperación está reconciliando.
// Nada de eso es raro: los triggers de §5.2 son automáticos y el usuario aprieta
// botones cuando quiere.

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

SpecRegistry _registro() => SpecRegistry([
      SyncSpec.push('venta'),
      SyncSpec.pull('producto'),
    ], allEntities: {
      'venta',
      'producto'
    });

void main() {
  test('dos backupNow() a la vez no bifurcan la cadena', () async {
    final drive = FakeArchive(authorized: true);
    final service = BackupService(
      archive: drive,
      crypto: FakeCrypto(),
      snapshot: FakeSnapshot()..state = {'venta': []},
    );

    // El del cierre de jornada y el que apretó el colportor, a la vez.
    await Future.wait([
      service.backupNow(watermark: 'w-1'),
      service.backupNow(watermark: 'w-1'),
    ]);

    final cadena = buildChain(await drive.list());
    expect(cadena.problems, isNot(contains(ChainProblem.fork)),
        reason: 'dos entradas con el mismo padre dejan la cadena inservible: '
            'no hay forma de saber cuál rama es la buena');
    expect(cadena.ok, isTrue);
  });

  test('recover() no se pisa con un ciclo automático', () async {
    final jobs = InMemoryJobStore();
    final transport = FakeSyncTransport();
    final red = FakeConnectivityPort();
    final motor = SyncEngine(
      specs: _registro(),
      transport: transport,
      jobs: jobs,
      store: InMemoryLocalStore(),
      connectivity: red,
    );

    await motor.stage('venta', Op.insert, {'id': 'v-1'}, clientOpId: 'op-1');
    transport.seed('producto', [
      {'id': 'p-1'},
    ]);

    // El wizard arranca la recuperación y justo vuelve la red.
    final recuperacion = motor.recover();
    red
      ..goOffline()
      ..goOnline();
    await recuperacion;
    await motor.settled;

    expect(transport.rowsOf('venta'), hasLength(1),
        reason: 'dos ciclos pisándose mandarían la misma venta dos veces');
    expect(jobs.withState(JobState.inFlight), isEmpty);
    expect(jobs.withState(JobState.pending), isEmpty);

    await motor.dispose();
  });
}
