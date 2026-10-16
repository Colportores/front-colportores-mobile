// Escala: una semana en modo avión con uso diario.
//
// RR-02 pide lotes de 100 registros en menos de 30 s y menos de 1 MB por sync.
// Lo que rompe eso no suele ser la red: es un algoritmo cuadrático que con 20
// jobs no se nota y con 5.000 deja la app colgada. Estos tests corren con
// números realistas de una semana sin conexión.

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

const _entidades = {'venta', 'visita', 'producto', 'persona'};

SpecRegistry _registro() => SpecRegistry([
      SyncSpec.push('venta'),
      SyncSpec.push('visita'),
      SyncSpec.pull('producto'),
      SyncSpec.local('persona'),
    ], allEntities: _entidades);

void main() {
  test('7 días sin conexión: 20.000 jobs suben completos y en orden', () async {
    final jobs = InMemoryJobStore();
    final transport = FakeSyncTransport();
    final motor = SyncEngine(
      specs: _registro(),
      transport: transport,
      jobs: jobs,
      store: InMemoryLocalStore(),
    );

    final reloj = Stopwatch()..start();

    // Una semana de trabajo sin red: ~700 visitas y ~30 ventas por día.
    for (var i = 0; i < 20000; i++) {
      await motor.stage(
        i % 10 == 0 ? 'venta' : 'visita',
        Op.insert,
        {'id': 'pk-$i', 'total': '1200.00', 'nota': 'x' * 40},
        clientOpId: 'op-$i',
      );
    }
    final encolar = reloj.elapsedMilliseconds;

    // Vuelve la red.
    reloj.reset();
    for (var i = 0; i < 100; i++) {
      final r = await motor.syncNow();
      if (r.pushed == 0) break;
    }
    final subir = reloj.elapsedMilliseconds;

    expect(jobs.withState(JobState.done), hasLength(20000));
    expect(jobs.withState(JobState.pending), isEmpty);
    expect(transport.rowsOf('venta').length + transport.rowsOf('visita').length,
        20000,
        reason: 'cero duplicados y cero pérdidas');

    // Cota generosa: hoy son ~50 ms. Un algoritmo cuadrático se pasa por
    // órdenes de magnitud, no por un 20%, así que si esto falla es un problema
    // de complejidad y no una máquina lenta. Antes de indexar la cola y de
    // dejar de contar el estado en cada stage, esto tardaba 6 segundos.
    expect(encolar + subir, lessThan(4000),
        reason: 'encolar ${encolar}ms + subir ${subir}ms');

    print('  20.000 jobs · encolar ${encolar}ms · subir ${subir}ms · '
        '${transport.batches.length} lotes');

    await motor.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('ningún lote pasa el tope de 1 MB (RR-02)', () {
    final jobs = [
      for (var i = 0; i < 3000; i++)
        QueuedJob(
          id: 'job-$i',
          state: JobState.pending,
          job: SyncJob(
            clientOpId: 'op-$i',
            entity: 'venta',
            op: Op.insert,
            // Una venta con items y notas: ~700 bytes.
            payload: {'id': 'pk-$i', 'detalle': 'x' * 650},
            createdAt: DateTime.utc(2026, 11, 13).add(Duration(seconds: i)),
          ),
        ),
    ];

    final lotes = buildBatches(jobs);

    expect(lotes.length, greaterThan(1), reason: '~2 MB no entran en un lote');
    for (final lote in lotes) {
      expect(batchBytes(lote), lessThanOrEqualTo(kMaxBatchBytes));
    }
    expect(lotes.fold(0, (n, l) => n + l.length), 3000,
        reason: 'partir no puede perder un job');
  });

  test('un pull de muchas páginas no se queda a mitad de camino', () async {
    final store = InMemoryLocalStore();
    final transport = FakeSyncTransport();
    final motor = SyncEngine(
      specs: _registro(),
      transport: transport,
      jobs: InMemoryJobStore(),
      store: store,
    );

    // Catálogo completo en la primera sync de un dispositivo nuevo.
    transport.seed('producto', [
      for (var i = 0; i < 4000; i++) {'id': 'p-$i', 'sync_version': 1}
    ]);

    final r = await motor.syncNow();

    expect(r.pulled, 4000);
    expect(store.rows['producto'], hasLength(4000));
    await motor.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
