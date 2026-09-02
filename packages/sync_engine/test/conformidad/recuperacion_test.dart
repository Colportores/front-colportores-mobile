// Suite de conformidad (§8) — el escenario de recuperación de dispositivo.
//
//   "Sobre FakeSyncTransport, un recover() con backup viejo + jobs ya subidos +
//    ventas posteriores en el servidor termina con: cero duplicados, las ventas
//    del servidor presentes, persona/nota del backup presentes, y el reporte
//    con la ventana perdida correcta. El mismo escenario sin backup recupera lo
//    sincronizado y reporta la pérdida de PII."

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

const _entidades = {'venta', 'producto', 'ubicacion', 'persona', 'nota'};

SpecRegistry _registro() => SpecRegistry([
      SyncSpec.push('venta', critical: true),
      SyncSpec.push('ubicacion', alsoPull: true),
      SyncSpec.pull('producto', realtime: true),
      SyncSpec.local('persona'),
      SyncSpec.local('nota'),
    ], allEntities: _entidades);

final _backupDate = DateTime.utc(2026, 11, 10, 20, 0);
final _ahora = DateTime.utc(2026, 11, 13, 8, 0); // 60 h después

/// Arma el celular nuevo: DB vacía, y el Drive con lo que dejó el viejo.
({
  SyncEngine motor,
  InMemoryJobStore jobs,
  InMemoryLocalStore store,
  FakeSyncTransport transport,
  FakeArchive drive,
  FakeSnapshot snap,
}) _celularNuevo({required bool conBackup}) {
  final jobs = InMemoryJobStore();
  final store = InMemoryLocalStore();
  final transport = FakeSyncTransport();
  final drive = FakeArchive(authorized: conBackup, clock: () => _backupDate);

  // Al restaurar, los jobs que estaban en sync_queue al momento del backup
  // vuelven a existir (§7 fase 1).
  final snap = FakeSnapshot(onRestore: (restaurado) {
    for (final fila in (restaurado['sync_queue'] as List? ?? [])) {
      final j = fila as Map<String, Object?>;
      jobs.append(SyncJob(
        clientOpId: j['client_op_id']! as String,
        entity: j['entity']! as String,
        op: Op.insert,
        payload: {'id': j['pk']},
        createdAt: _backupDate,
      ));
    }
    for (final tabla in ['persona', 'nota', 'venta']) {
      final filas = restaurado[tabla] as List?;
      if (filas != null) {
        (store.rows[tabla] ??= []).addAll(filas.cast<Map<String, Object?>>());
      }
    }
  });

  return (
    motor: SyncEngine(
      specs: _registro(),
      transport: transport,
      jobs: jobs,
      store: store,
      clock: () => _ahora,
      backup: BackupService(
        archive: drive,
        crypto: FakeCrypto(),
        snapshot: snap,
        clock: () => _backupDate,
      ),
    ),
    jobs: jobs,
    store: store,
    transport: transport,
    drive: drive,
    snap: snap,
  );
}

/// El backup que dejó el celular perdido: PII, y una venta que quedó encolada
/// sin subir.
Future<void> _dejarBackup(
  FakeArchive drive,
  FakeSnapshot snap, {
  required String watermark,
}) async {
  snap.state = {
    // Lo que el celular perdido tenía en la DB al momento del backup: su PII,
    // y las ventas que ya había sincronizado hasta ahí.
    'venta': [
      {'id': 'v-vieja', 'total': '1200.00'}
    ],
    'persona': [
      {'id': 'per-1', 'nombre': 'Ana Gómez'}
    ],
    'nota': [
      {'id': 'not-1', 'texto': 'volver el jueves'}
    ],
    'sync_queue': [
      {'client_op_id': 'op-encolada', 'entity': 'venta', 'pk': 'v-encolada'},
    ],
  };
  await BackupService(
    archive: drive,
    crypto: FakeCrypto(),
    snapshot: snap,
    clock: () => _backupDate,
  ).backupNow(watermark: watermark);
}

void main() {
  test('con backup: fusiona Drive y Supabase, sin duplicar nada', () async {
    final (:motor, :jobs, :store, :transport, :drive, :snap) =
        _celularNuevo(conBackup: true);

    // El celular viejo había subido esta venta antes del backup...
    transport.seed('venta', [
      {'id': 'v-vieja', 'total': '1200.00'}
    ]);
    await _dejarBackup(drive, snap, watermark: 'w-1');

    // ...y después del backup subió otra, antes de perderse.
    transport.seed('venta', [
      {'id': 'v-posterior', 'total': '800.00'}
    ]);
    // El colportor ya había subido, desde el celu viejo, la venta que en el
    // backup figura como encolada: el replay va a reencontrarla.
    await transport.push(PushBatch([
      SyncJob(
        clientOpId: 'op-vieja-subida',
        entity: 'venta',
        op: Op.insert,
        payload: {'id': 'v-encolada'},
        createdAt: _backupDate,
      )
    ]));
    transport.seed('producto', [
      {'id': 'p-1', 'nombre': 'El Camino a Cristo'}
    ]);

    final reporte = await motor.recover();

    // Cero duplicados: la venta encolada ya estaba, el replay no creó otra.
    expect(transport.rowsOf('venta').map((f) => f['id']),
        unorderedEquals(['v-vieja', 'v-posterior', 'v-encolada']));
    expect(jobs.withState(JobState.done), hasLength(1),
        reason: 'el job replayeado se cierra, no queda INVALID');
    expect(jobs.withState(JobState.invalid), isEmpty);

    // Las ventas del servidor están.
    final ventasLocales = store.rows['venta']!.map((f) => f['id']).toList();
    expect(ventasLocales, containsAll(['v-vieja', 'v-posterior']));

    // La PII del backup está.
    expect(store.rows['persona']!.single['nombre'], 'Ana Gómez');
    expect(store.rows['nota']!.single['texto'], 'volver el jueves');

    // Los catálogos se replican frescos, no salen del backup.
    expect(store.rows['producto'], hasLength(1));

    // Y el reporte dice la verdad.
    expect(reporte.backupDate, _backupDate);
    expect(reporte.replayedJobs, 1);
    expect(reporte.lostWindow!.from, _backupDate);
    expect(reporte.lostWindow!.to, _ahora);
    expect(reporte.lostWindow!.length.inHours, 60);
    expect(reporte.lostPersonalData, isFalse);
    expect(reporte.pulledEntities['venta'], 2,
        reason: 'la reconciliación trae lo posterior al backup: v-posterior y '
            'v-encolada. v-vieja ya venía en la DB restaurada');

    await motor.dispose();
  });

  test('sin backup: recupera lo sincronizado y avisa que la PII se perdió',
      () async {
    final (:motor, :store, :transport, jobs: _, drive: _, snap: _) =
        _celularNuevo(conBackup: false);

    transport.seed('venta', [
      {'id': 'v-vieja'},
      {'id': 'v-posterior'}
    ]);
    transport.seed('producto', [
      {'id': 'p-1'}
    ]);

    final reporte = await motor.recover();

    expect(store.rows['venta'], hasLength(2),
        reason: 'todo lo que había sincronizado vuelve');
    expect(store.rows['producto'], hasLength(1));
    expect(store.rows.containsKey('persona'), isFalse);

    expect(reporte.hadBackup, isFalse);
    expect(reporte.backupDate, isNull);
    expect(reporte.replayedJobs, 0);
    expect(reporte.lostWindow, isNull,
        reason: 'sin backup la pérdida no es una ventana: es toda la PII');
    expect(reporte.lostPersonalData, isTrue);

    await motor.dispose();
  });

  test('con la cadena rota se recupera igual, y el reporte dice por qué',
      () async {
    final (:motor, :store, :transport, :drive, :snap, jobs: _) =
        _celularNuevo(conBackup: true);

    await _dejarBackup(drive, snap, watermark: 'w-1');
    await BackupService(
      archive: drive,
      crypto: FakeCrypto(),
      snapshot: snap,
      clock: () => _backupDate,
    ).backupNow(watermark: 'w-2');
    drive.deleteEntry('backup-1'); // se voló la base

    transport.seed('venta', [
      {'id': 'v-posterior'}
    ]);
    final reporte = await motor.recover();

    expect(reporte.hadBackup, isFalse);
    expect(reporte.chainProblem, isNotEmpty);
    expect(reporte.lostPersonalData, isTrue);
    expect(store.rows['venta'], hasLength(1),
        reason:
            'lo sincronizado se recupera igual: son fuentes independientes');

    await motor.dispose();
  });

  test('la reconciliación arranca del watermark del backup, no de cero',
      () async {
    final (:motor, :store, :transport, :drive, :snap, jobs: _) =
        _celularNuevo(conBackup: true);

    transport.seed('ubicacion', [
      {'id': 'u-antes'}
    ]);
    // El backup se hizo con esa fila ya aplicada localmente.
    await _dejarBackup(drive, snap, watermark: 'w-1');
    transport.seed('ubicacion', [
      {'id': 'u-despues'}
    ]);

    await motor.recover();

    expect(store.rows['ubicacion']!.map((f) => f['id']), ['u-despues'],
        reason: 'lo anterior al backup ya estaba en la DB restaurada');

    await motor.dispose();
  });
}
