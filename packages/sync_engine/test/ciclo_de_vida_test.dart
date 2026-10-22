// El motor tiene un ciclo de vida atado al de la app.
//
// `flush()` es lo que la app llama cuando Android le avisa que la manda a
// segundo plano: si vuelve antes de que el dato salga, la promesa no vale nada.
// Y `dispose()` tiene que dejar el motor quieto de verdad.

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

SpecRegistry _registro() => SpecRegistry([
      SyncSpec.push('venta', critical: true),
      SyncSpec.push('visita'),
      SyncSpec.pull('producto'),
    ], allEntities: {
      'venta',
      'visita',
      'producto'
    });

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
      criticalDebounce: const Duration(seconds: 30),
    ),
    jobs: jobs,
    transport: transport,
  );
}

void main() {
  test('flush() espera de verdad, aunque haya un ciclo corriendo', () async {
    final (:motor, :jobs, :transport) = _armar();

    // Algo ya está subiendo…
    await motor.stage('visita', Op.insert, {'id': 'vi-1'}, clientOpId: 'op-vi');
    final enCurso = motor.syncNow();

    // …y el colportor cierra una venta justo antes de que Android mande la app
    // a segundo plano.
    await motor.stage('venta', Op.insert, {'id': 'v-1'}, clientOpId: 'op-v');
    await motor.flush();

    expect(transport.rowsOf('venta'), hasLength(1),
        reason: 'si flush() vuelve antes de que la venta salga, la app se va a '
            'segundo plano con el dato adentro');
    expect(jobs.withState(JobState.pending), isEmpty);

    await enCurso;
    await motor.dispose();
  });

  test('flush() sin nada pendiente no cuelga', () async {
    final (:motor, transport: _, jobs: _) = _armar();
    await motor.flush();
    await motor.dispose();
  });

  test('después de dispose() el motor queda quieto', () async {
    final (:motor, :transport, jobs: _) = _armar();
    await motor.dispose();

    expect(
      () => motor.stage('venta', Op.insert, {'id': 'v-1'}, clientOpId: 'op-1'),
      throwsStateError,
      reason: 'encolar en un motor apagado es perder el dato en silencio: '
          'nadie lo va a subir',
    );
    expect(motor.syncNow, throwsStateError);
    expect(transport.batches, isEmpty);
  });

  test('dispose() dos veces no explota', () async {
    final (:motor, transport: _, jobs: _) = _armar();
    await motor.dispose();
    await motor.dispose();
  });
}
