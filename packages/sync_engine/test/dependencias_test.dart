// Un agujero conocido: dependencias entre entidades.
//
// §2 declara `venta` y `venta_item` como dos entidades push separadas, pero el
// contrato v0.9.2 no dice nada sobre qué pasa cuando una depende de la otra.
// Estos tests documentan el comportamiento actual —incluido el caso malo— para
// que la decisión se tome mirando el problema y no después de verlo en
// producción.
//
// Ver "Dependencias entre entidades" en el README.

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

const _entidades = {'venta', 'venta_item', 'persona'};

SpecRegistry _registro() => SpecRegistry([
      SyncSpec.push('venta'),
      SyncSpec.push('venta_item'),
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

void main() {
  test('lo que sí está garantizado: el orden de creación se respeta', () async {
    final (:motor, jobs: _, :transport) = _armar();

    await motor.stage('venta', Op.insert, {'id': 'v-1'}, clientOpId: 'op-v');
    await motor.stage('venta_item', Op.insert, {'id': 'i-1', 'pk_venta': 'v-1'},
        clientOpId: 'op-i');
    await motor.syncNow();

    final llegada = transport.batches.single.jobs.map((j) => j.entity);
    expect(llegada, ['venta', 'venta_item'],
        reason: '§5.5: un item nunca viaja antes que su venta');
  });

  test('el orden se conserva aunque el lote se parta', () async {
    final (:motor, jobs: _, :transport) = _armar();

    for (var i = 0; i < 6; i++) {
      await motor.stage('venta', Op.insert, {'id': 'v-$i'},
          clientOpId: 'op-v-$i');
      await motor.stage(
          'venta_item', Op.insert, {'id': 'i-$i', 'pk_venta': 'v-$i'},
          clientOpId: 'op-i-$i');
    }
    await motor.syncNow();

    final orden = [
      for (final lote in transport.batches)
        for (final job in lote.jobs) job.clientOpId,
    ];
    for (var i = 0; i < 6; i++) {
      expect(orden.indexOf('op-v-$i'), lessThan(orden.indexOf('op-i-$i')),
          reason: 'venta $i tiene que ir antes que su item');
    }
  });

  test(
      'AGUJERO: si la venta queda INVALID, su item entra igual y queda huérfano',
      () async {
    final (:motor, :jobs, :transport) = _armar();

    final idVenta = await motor.stage('venta', Op.insert, {'id': 'v-1'},
        clientOpId: 'op-v');
    final idItem = await motor.stage(
        'venta_item', Op.insert, {'id': 'i-1', 'pk_venta': 'v-1'},
        clientOpId: 'op-i');

    // El backend rechaza la venta —un producto que no existe, una campaña
    // cerrada— pero el item viene en el mismo lote y no tiene nada de malo.
    transport.rejectJob('op-v', 'PRODUCTO_INEXISTENTE');
    await motor.syncNow();

    expect(jobs.byId(idVenta).state, JobState.invalid);
    expect(jobs.byId(idItem).state, JobState.done);

    expect(transport.rowsOf('venta'), isEmpty);
    expect(transport.rowsOf('venta_item'), hasLength(1),
        reason: 'ESTE es el problema: hay un item en el servidor cuya venta no '
            'existe. Si el colportor corrige la venta y la reencola, queda '
            'bien; si la descarta, el item queda huérfano para siempre.');
  });

  test('lo mismo con una falla transitoria NO pasa: el ciclo se corta entero',
      () async {
    final (:motor, :jobs, :transport) = _armar();

    final idVenta = await motor.stage('venta', Op.insert, {'id': 'v-1'},
        clientOpId: 'op-v');
    final idItem = await motor.stage(
        'venta_item', Op.insert, {'id': 'i-1', 'pk_venta': 'v-1'},
        clientOpId: 'op-i');

    transport.failTransient();
    await motor.syncNow();

    expect(jobs.byId(idVenta).state, JobState.pending);
    expect(jobs.byId(idItem).state, JobState.pending,
        reason: 'los dos vuelven juntos: una caída de red no separa una venta '
            'de sus items');
    expect(transport.rowsOf('venta_item'), isEmpty);
  });

  test('requeue de la venta arregla el huérfano', () async {
    final (:motor, :jobs, :transport) = _armar();

    final idVenta = await motor.stage('venta', Op.insert, {'id': 'v-1'},
        clientOpId: 'op-v');
    await motor.stage('venta_item', Op.insert, {'id': 'i-1', 'pk_venta': 'v-1'},
        clientOpId: 'op-i');

    transport.rejectJob('op-v', 'PRODUCTO_INEXISTENTE');
    await motor.syncNow();

    // El colportor corrige el producto en la app y reencola.
    transport.clearRejections();
    await motor.requeue(idVenta);
    await motor.syncNow();

    expect(jobs.byId(idVenta).state, JobState.done);
    expect(transport.rowsOf('venta'), hasLength(1),
        reason: 'el camino de salida existe: la cola de error es visible y '
            'requeue() la resuelve');
  });
}
