// §5.4: el servidor gana por `sync_version` y el motor aplica su fila sin ir a
// la cola de error. Dos cosas que ese camino tiene que cuidar:
//
// - no inventa un watermark: guardar `''` si no había ninguno rompe la fase 3
//   de `recover()`, porque el backend contesta 22023 a un watermark vacío;
// - si aplicar la fila del servidor revienta (la DB local falla), lo que ese
//   mismo lote ya aceptó se cierra igual: no queda `IN_FLIGHT` hasta el lease.

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

/// Contesta lo que diga [resultados], por `client_op_id`, y nada más.
class _Guionado implements SyncTransport {
  _Guionado(this.resultados);

  final Map<String, JobResult> resultados;
  final List<List<String>> lotes = [];
  final List<String?> watermarksPedidos = [];

  @override
  Future<PushResult> push(PushBatch batch) async {
    lotes.add([for (final j in batch.jobs) j.clientOpId]);
    return PushResult(
      serverTime: DateTime.utc(2026, 10, 21),
      results: [for (final j in batch.jobs) resultados[j.clientOpId]!],
    );
  }

  @override
  Future<PullDelta> pull({
    required List<String> entities,
    String? watermark,
    int? limit,
  }) async {
    watermarksPedidos.add(watermark);
    return PullDelta(
      serverTime: DateTime.utc(2026, 10, 21),
      watermark: 'w-pull',
      hasMore: false,
      rows: const {},
    );
  }
}

({
  SyncEngine motor,
  _Guionado servidor,
  InMemoryJobStore cola,
  InMemoryLocalStore filas,
})
_armar(Map<String, JobResult> resultados) {
  final servidor = _Guionado(resultados);
  final cola = InMemoryJobStore();
  final filas = InMemoryLocalStore();
  final motor = SyncEngine(
    specs: SpecRegistry([SyncSpec.push('jornada')], allEntities: {'jornada'}),
    transport: servidor,
    jobs: cola,
    store: filas,
  );
  return (motor: motor, servidor: servidor, cola: cola, filas: filas);
}

JobState _estado(InMemoryJobStore cola, String opId) =>
    cola.all.firstWhere((q) => q.job.clientOpId == opId).state;

void main() {
  group('M1 · el LWW no toca el watermark', () {
    test('sin watermark previo no guarda uno vacío', () async {
      final (:motor, :servidor, :cola, :filas) = _armar({
        'op-1': const JobResult(
          clientOpId: 'op-1',
          outcome: JobOutcome.conflict,
          serverRow: {'id': 'j-1', 'fin': 'del-servidor', 'sync_version': 4},
        ),
      });
      await motor.stage(
        'jornada',
        Op.update,
        {'id': 'j-1', 'fin': 'del-telefono'},
        clientOpId: 'op-1',
        syncVersion: 1,
      );

      final r = await motor.syncNow();

      expect(r.conflicts, 1);
      expect(filas.rows['jornada']!.single['fin'], 'del-servidor');
      expect(
        filas.watermarks.containsKey('mirror'),
        isFalse,
        reason: '`\'\'` hace que el backend conteste 22023 en recover()',
      );
      expect(_estado(cola, 'op-1'), JobState.done);
      await motor.dispose();
    });

    test('con watermark previo lo deja como estaba', () async {
      final (:motor, :servidor, :cola, :filas) = _armar({
        'op-1': const JobResult(
          clientOpId: 'op-1',
          outcome: JobOutcome.conflict,
          serverRow: {'id': 'j-1', 'sync_version': 4},
        ),
      });
      filas.watermarks['mirror'] = 'w-previo';
      await motor.stage(
        'jornada',
        Op.update,
        {'id': 'j-1'},
        clientOpId: 'op-1',
        syncVersion: 1,
      );

      await motor.syncNow();

      expect(filas.watermarks['mirror'], 'w-previo');
      await motor.dispose();
    });
  });

  group('M2 · aplicar la fila del servidor revienta a mitad del lote', () {
    test(
      'lo aceptado antes se cierra y su versión vuelve; lo que reventó, PENDING',
      () async {
        final (:motor, :servidor, :cola, :filas) = _armar({
          'op-ok': const JobResult(
            clientOpId: 'op-ok',
            outcome: JobOutcome.accepted,
            syncVersion: 3,
          ),
          'op-lww': const JobResult(
            clientOpId: 'op-lww',
            outcome: JobOutcome.conflict,
            serverRow: {'id': 'j-2', 'sync_version': 9},
          ),
        });
        filas.rows['jornada'] = [
          {'id': 'j-1', 'sync_version': 2},
        ];
        await motor.stage(
          'jornada',
          Op.update,
          {'id': 'j-1', 'fin': 'x'},
          clientOpId: 'op-ok',
          syncVersion: 2,
        );
        await motor.stage(
          'jornada',
          Op.update,
          {'id': 'j-2', 'fin': 'y'},
          clientOpId: 'op-lww',
          syncVersion: 1,
        );
        filas.failOnApply = true;

        await expectLater(motor.syncNow(), throwsA(isA<StateError>()));

        expect(servidor.lotes, [
          ['op-ok', 'op-lww'],
        ]);
        expect(
          _estado(cola, 'op-ok'),
          JobState.done,
          reason: 'el servidor ya lo aceptó: no puede quedar IN_FLIGHT',
        );
        expect(_estado(cola, 'op-lww'), JobState.pending);
        expect((await cola.status()).inFlight, 0);
        expect(
          filas.rows['jornada']!.single['sync_version'],
          3,
          reason: 'la versión del servidor volvió a la fila',
        );

        // Con la DB sana, el que reventó se reintenta y se resuelve.
        filas.failOnApply = false;
        final r = await motor.syncNow();
        expect(r.conflicts, 1);
        expect(_estado(cola, 'op-lww'), JobState.done);
        await motor.dispose();
      },
    );
  });
}
