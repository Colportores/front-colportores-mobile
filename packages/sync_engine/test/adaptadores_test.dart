// stageRow: la forma tipada de encolar, con el SyncTableAdapter como única
// fuente de la entidad, el payload y la sync_version (§3).

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

class Venta {
  const Venta({required this.id, required this.total, this.syncVersion = 1});
  final String id;
  final String total;
  final int syncVersion;
}

class VentaAdapter extends SyncTableAdapter<Venta> {
  const VentaAdapter();

  @override
  String get remoteName => 'venta';

  @override
  Map<String, Object?> toSyncJson(Venta row) =>
      {'id': row.id, 'total': row.total, 'sync_version': row.syncVersion};

  @override
  Venta fromSyncJson(Map<String, Object?> json) => Venta(
        id: json['id']! as String,
        total: json['total']! as String,
        syncVersion: json['sync_version']! as int,
      );

  @override
  Object pkOf(Venta row) => row.id;

  @override
  int syncVersionOf(Venta row) => row.syncVersion;
}

({SyncEngine motor, InMemoryJobStore jobs, FakeSyncTransport transport})
    _armar() {
  final jobs = InMemoryJobStore();
  final transport = FakeSyncTransport();
  return (
    motor: SyncEngine(
      specs: SpecRegistry([
        SyncSpec.push('venta'),
        SyncSpec.local('persona'),
      ], allEntities: {
        'venta',
        'persona'
      }),
      transport: transport,
      jobs: jobs,
      store: InMemoryLocalStore(),
      adapters: const [VentaAdapter()],
    ),
    jobs: jobs,
    transport: transport,
  );
}

void main() {
  test('el motor genera el client_op_id (§3, §5.3)', () async {
    final (:motor, :jobs, transport: _) = _armar();

    await motor.stage('venta', Op.insert, {'id': 'v-1'});
    await motor.stage('venta', Op.insert, {'id': 'v-2'});

    final opIds = jobs.all.map((j) => j.job.clientOpId).toList();
    expect(opIds.toSet(), hasLength(2), reason: 'uno por job, sin repetir');
    expect(opIds.first, matches(RegExp('-7[0-9a-f]{3}-')),
        reason: 'v7: ordenable por tiempo');
    await motor.dispose();
  });

  test('stageRow saca todo del adaptador', () async {
    final (:motor, :jobs, transport: _) = _armar();

    await motor.stageRow(const Venta(id: 'v-1', total: '1200.00'), Op.insert);

    final job = jobs.all.single.job;
    expect(job.entity, 'venta');
    expect(job.payload['total'], '1200.00');
    expect(job.syncVersion, isNull,
        reason: 'un insert no espera versión previa');
    await motor.dispose();
  });

  test('un update lleva la sync_version esperada', () async {
    final (:motor, :jobs, transport: _) = _armar();

    await motor.stageRow(
        const Venta(id: 'v-1', total: '1300.00', syncVersion: 4), Op.update);

    expect(jobs.all.single.job.syncVersion, 4);
    await motor.dispose();
  });

  test('sin adaptador registrado, stageRow lo dice', () async {
    final (:motor, jobs: _, transport: _) = _armar();
    expect(() => motor.stageRow('una String', Op.insert), throwsStateError);
    await motor.dispose();
  });

  test('stageRow no puede saltear la regla de las entidades local', () async {
    // La única forma de stagear es a través del adaptador, y las entidades
    // local no tienen: no hay manera de mandar una persona al servidor.
    final (:motor, jobs: _, transport: _) = _armar();
    expect(motor.adapterOf('persona'), isNull);
    await expectLater(
      motor.stage('persona', Op.insert, {'id': 'p-1'}),
      throwsA(isA<LocalOnlyViolationError>()),
    );
    await motor.dispose();
  });

  test('lo stageado con stageRow llega bien al servidor', () async {
    final (:motor, jobs: _, :transport) = _armar();

    await motor.stageRow(const Venta(id: 'v-1', total: '1200.00'), Op.insert);
    await motor.syncNow();

    expect(transport.rowsOf('venta').single['total'], '1200.00');
    await motor.dispose();
  });
}
