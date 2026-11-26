// §2.3 «Venta tarde» y §6.1: cuando el servidor contesta `merged` con `merged_into`, el motor cierra
// el job (DONE) **y reapunta lo local** a la fila que quedó, antes de cerrarlo. Acá, el motor contra
// un servidor que contesta lo que se le dice y los almacenes en memoria (lo que reescribe cada tabla
// lo prueba `drift_local_store_reapuntar_770_test.dart`, en la app).
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

/// Un servidor que responde a cada job con lo que dice [respuesta] (por `client_op_id`); lo que no
/// nombra, lo acepta.
final class _Servidor implements SyncTransport {
  _Servidor(this.respuesta);

  final Map<String, JobResult> respuesta;
  int pushes = 0;

  @override
  Future<PushResult> push(PushBatch batch) async {
    pushes++;
    return PushResult(
      serverTime: DateTime.utc(2026, 11, 25, 12),
      results: [
        for (final j in batch.jobs)
          respuesta[j.clientOpId] ??
              JobResult(
                clientOpId: j.clientOpId,
                outcome: JobOutcome.accepted,
                syncVersion: 1,
              ),
      ],
    );
  }

  @override
  Future<PullDelta> pull({
    required List<String> entities,
    String? watermark,
    int? limit,
  }) async => PullDelta(
    serverTime: DateTime.utc(2026, 11, 25, 12),
    watermark: watermark ?? 'w-0',
    hasMore: false,
    rows: const {},
  );
}

({
  SyncEngine motor,
  _Servidor servidor,
  InMemoryJobStore cola,
  InMemoryLocalStore filas,
})
_armar(Map<String, JobResult> respuesta) {
  final servidor = _Servidor(respuesta);
  final cola = InMemoryJobStore();
  final filas = InMemoryLocalStore();
  final motor = SyncEngine(
    specs: SpecRegistry(
      [SyncSpec.push('espacio_persona'), SyncSpec.push('venta')],
      allEntities: {'espacio_persona', 'venta'},
    ),
    transport: servidor,
    jobs: cola,
    store: filas,
  );
  return (motor: motor, servidor: servidor, cola: cola, filas: filas);
}

JobResult _merged(String op, {String? en = 'ep-y'}) =>
    JobResult(clientOpId: op, outcome: JobOutcome.merged, mergedInto: en);

void main() {
  test('merged con merged_into: el store reapunta el vínculo y el job queda '
      'DONE', () async {
    final (:motor, :servidor, :cola, :filas) = _armar({
      'op-vinculo': _merged('op-vinculo'),
    });
    filas.rows['espacio_persona'] = [
      {'id': 'ep-x', 'persona_id': 'per-1'},
    ];
    await motor.stage('espacio_persona', Op.insert, {
      'id': 'ep-x',
    }, clientOpId: 'op-vinculo');
    await motor.stage('venta', Op.insert, {
      'id': 'ven-1',
      'espacio_persona_id': 'ep-x',
    }, clientOpId: 'op-venta');

    final salida = await motor.syncNow();
    await motor.dispose();

    expect(filas.reapuntados, [('espacio_persona', 'ep-x', 'ep-y')]);
    expect(filas.rows['espacio_persona']!.single['id'], 'ep-y');
    expect(salida.invalidated, 0);
    expect(
      salida.pushed,
      2,
      reason: 'el merged cuenta como aplicado, la venta también',
    );
    expect(cola.withState(JobState.done), hasLength(2));
    expect(cola.withState(JobState.invalid), isEmpty);
  });

  test('merged sin merged_into (un servidor que no lo manda): DONE y no '
      'reapunta a nadie', () async {
    final (:motor, :servidor, :cola, :filas) = _armar({
      'op-vinculo': _merged('op-vinculo', en: null),
    });
    await motor.stage('espacio_persona', Op.insert, {
      'id': 'ep-x',
    }, clientOpId: 'op-vinculo');

    await motor.syncNow();
    await motor.dispose();

    expect(filas.reapuntados, isEmpty);
    expect(cola.withState(JobState.done), hasLength(1));
  });

  test('merged_into igual al propio id: no hay nada que reapuntar', () async {
    final (:motor, :servidor, :cola, :filas) = _armar({
      'op-vinculo': _merged('op-vinculo', en: 'ep-x'),
    });
    await motor.stage('espacio_persona', Op.insert, {
      'id': 'ep-x',
    }, clientOpId: 'op-vinculo');

    await motor.syncNow();
    await motor.dispose();

    expect(filas.reapuntados, isEmpty);
    expect(cola.withState(JobState.done), hasLength(1));
  });

  test('un accepted o un duplicate no reapuntan nada', () async {
    final (:motor, :servidor, :cola, :filas) = _armar({
      'op-dup': const JobResult(
        clientOpId: 'op-dup',
        outcome: JobOutcome.duplicate,
      ),
    });
    await motor.stage('espacio_persona', Op.insert, {
      'id': 'ep-x',
    }, clientOpId: 'op-dup');
    await motor.stage('espacio_persona', Op.insert, {
      'id': 'ep-z',
    }, clientOpId: 'op-ok');

    await motor.syncNow();
    await motor.dispose();

    expect(filas.reapuntados, isEmpty);
  });

  test('si reapuntar falla, el job NO queda cerrado: vuelve a PENDING y el '
      'reintento (otro merged igual) lo termina', () async {
    final (:motor, :servidor, :cola, :filas) = _armar({
      'op-vinculo': _merged('op-vinculo'),
    });
    await motor.stage('espacio_persona', Op.insert, {
      'id': 'ep-x',
    }, clientOpId: 'op-vinculo');

    filas.failOnReapuntar = true;
    await expectLater(motor.syncNow(), throwsStateError);
    expect(
      cola.withState(JobState.done),
      isEmpty,
      reason:
          'cerrarlo sin reapuntar dejaría la venta colgada de un id que no existe',
    );
    expect(cola.withState(JobState.pending), hasLength(1));
    expect(
      cola.withState(JobState.inFlight),
      isEmpty,
      reason: 'ningún job queda trabado en vuelo',
    );

    filas.failOnReapuntar = false;
    await motor.syncNow();
    await motor.dispose();

    expect(filas.reapuntados, [('espacio_persona', 'ep-x', 'ep-y')]);
    expect(cola.withState(JobState.done), hasLength(1));
    expect(servidor.pushes, 2);
  });

  test('un merged no frena al resto del lote ni se vuelve a subir', () async {
    final (:motor, :servidor, :cola, :filas) = _armar({
      'op-vinculo': _merged('op-vinculo'),
    });
    await motor.stage('espacio_persona', Op.insert, {
      'id': 'ep-x',
    }, clientOpId: 'op-vinculo');
    await motor.stage('venta', Op.insert, {
      'id': 'ven-1',
      'espacio_persona_id': 'ep-x',
    }, clientOpId: 'op-venta');

    await motor.syncNow();
    await motor.syncNow();
    await motor.dispose();

    expect(
      servidor.pushes,
      1,
      reason: 'nada quedó pendiente: el 2.º ciclo no sube',
    );
    expect(filas.reapuntados, hasLength(1), reason: 'reapunta una sola vez');
  });
}
