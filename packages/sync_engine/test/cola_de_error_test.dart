// RF-SY06: el colportor tiene que poder ver qué quedó en error y qué hacer.
//
// `status` da los contadores para el banner; `errorQueue()` da la lista para la
// pantalla. Sin la segunda, `requeue(jobId)` es inalcanzable: la app no tiene
// de dónde sacar el id.

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

({SyncEngine motor, FakeSyncTransport transport}) _armar() {
  final transport = FakeSyncTransport();
  return (
    motor: SyncEngine(
      specs: SpecRegistry([
        SyncSpec.push('venta'),
        SyncSpec.push('visita'),
        SyncSpec.local('persona'),
      ], allEntities: {
        'venta',
        'visita',
        'persona'
      }),
      transport: transport,
      jobs: InMemoryJobStore(),
      store: InMemoryLocalStore(),
    ),
    transport: transport,
  );
}

void main() {
  test('trae lo que la pantalla necesita mostrar', () async {
    final (:motor, :transport) = _armar();

    await motor.stage('venta', Op.insert, {'id': 'v-1', 'total': '1200.00'},
        clientOpId: 'op-mala');
    await motor.stage('visita', Op.insert, {'id': 'vi-1'},
        clientOpId: 'op-buena');

    transport.rejectJob('op-mala', 'PRODUCTO_INEXISTENTE', 'pk_producto 812');
    await motor.syncNow();

    final enError = await motor.errorQueue();

    expect(enError, hasLength(1));
    final job = enError.single;
    expect(job.code, 'PRODUCTO_INEXISTENTE');
    expect(job.message, 'pk_producto 812');
    expect(job.job.entity, 'venta');
    expect(job.job.payload['total'], '1200.00',
        reason: 'la app muestra de qué venta se trata, no un id opaco');

    await motor.dispose();
  });

  test('el id que trae es el que acepta requeue()', () async {
    final (:motor, :transport) = _armar();

    await motor.stage('venta', Op.insert, {'id': 'v-1'}, clientOpId: 'op-1');
    transport.rejectJob('op-1', 'CAMPANIA_CERRADA');
    await motor.syncNow();

    // El colportor corrige el dato en la app y toca "reintentar".
    final job = (await motor.errorQueue()).single;
    transport.clearRejections();
    await motor.requeue(job.id);
    await motor.syncNow();

    expect(await motor.errorQueue(), isEmpty);
    expect(transport.rowsOf('venta'), hasLength(1));

    await motor.dispose();
  });

  test('un job pendiente o subido no aparece en la cola de error', () async {
    final (:motor, transport: _) = _armar();

    await motor.stage('venta', Op.insert, {'id': 'v-1'}, clientOpId: 'op-1');
    expect(await motor.errorQueue(), isEmpty, reason: 'todavía PENDING');

    await motor.syncNow();
    expect(await motor.errorQueue(), isEmpty, reason: 'ya DONE');

    await motor.dispose();
  });

  test('los contadores del banner y la lista dicen lo mismo', () async {
    final (:motor, :transport) = _armar();
    final vistos = <SyncStatus>[];
    final sub = motor.status.listen(vistos.add);

    for (var i = 0; i < 3; i++) {
      await motor.stage('venta', Op.insert, {'id': 'v-$i'},
          clientOpId: 'op-$i');
      transport.rejectJob('op-$i', 'X');
    }
    await motor.syncNow();
    await Future<void>.delayed(Duration.zero);

    expect(vistos.last.invalid, 3);
    expect(await motor.errorQueue(), hasLength(3));

    await sub.cancel();
    await motor.dispose();
  });
}
