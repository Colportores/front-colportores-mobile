import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

QueuedJob _job(String pk, {int relleno = 0, int orden = 0}) => QueuedJob(
      id: 'job-$pk',
      state: JobState.pending,
      job: SyncJob(
        clientOpId: 'op-$pk',
        entity: 'venta',
        op: Op.insert,
        payload: {'id': pk, 'notas': 'x' * relleno},
        createdAt: DateTime.utc(2026, 8, 28, 12, 0, orden),
      ),
    );

void main() {
  test('un lote chico viaja entero', () {
    final lotes = buildBatches([_job('v1'), _job('v2'), _job('v3')]);
    expect(lotes, hasLength(1));
    expect(lotes.single.length, 3);
  });

  test('el corte es por bytes, no por cantidad (§5.5)', () {
    final jobs = [for (var i = 0; i < 10; i++) _job('v$i', relleno: 400)];
    final lotes = buildBatches(jobs, maxBytes: 1000);

    expect(lotes.length, greaterThan(1));
    for (final lote in lotes) {
      expect(batchBytes(lote), lessThanOrEqualTo(1000),
          reason: 'salvo un job que solo no entre, ningún lote pasa el tope');
    }
  });

  test('el orden de creación se conserva a través de los lotes', () {
    final jobs = [
      for (var i = 0; i < 10; i++) _job('v$i', relleno: 400, orden: i)
    ];
    final ids = [
      for (final lote in buildBatches(jobs, maxBytes: 1000))
        for (final job in lote.jobs) job.payload['id'],
    ];

    expect(ids, [for (var i = 0; i < 10; i++) 'v$i'],
        reason: 'un update no puede adelantarse al insert de su propia fila');
  });

  test('un job que solo ya pasa el tope viaja igual, en su propio lote', () {
    final lotes = buildBatches(
      [_job('chico'), _job('gigante', relleno: 5000), _job('otro')],
      maxBytes: 1000,
    );

    final gigante = lotes
        .firstWhere((l) => l.jobs.any((j) => j.payload['id'] == 'gigante'));
    expect(gigante.length, 1);
    expect(batchBytes(gigante), greaterThan(1000),
        reason: 'descartarlo perdería una venta; que el backend lo rechace y '
            'quede INVALID es mejor que desaparecer en silencio');
  });
}
