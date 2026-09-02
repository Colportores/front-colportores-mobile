// Qué pasa con lo que estaba en vuelo cuando la app se muere.
//
// El colportor cierra la app, se queda sin batería, o Android mata el proceso
// para liberar memoria — cualquiera de las tres, a mitad de un push. Los jobs
// que el ciclo había pasado a IN_FLIGHT quedan así en sync_queue, y en el
// arranque siguiente `claimPending` solo mira los PENDING.

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

/// Un transporte que se cae de una forma que el motor no espera: no una
/// TransportFailure clasificada, sino cualquier otra cosa. Es lo que hace un
/// adaptador con un bug.
class TransporteRoto implements SyncTransport {
  @override
  Future<PushResult> push(PushBatch batch) async =>
      throw StateError('el adaptador explotó');

  @override
  Future<PullDelta> pull({
    required List<String> entities,
    String? watermark,
    int? limit,
  }) async =>
      throw StateError('el adaptador explotó');
}

void main() {
  test('un error inesperado del transporte no deja jobs colgados', () async {
    final jobs = InMemoryJobStore();
    final motor = SyncEngine(
      specs: _registro(),
      transport: TransporteRoto(),
      jobs: jobs,
      store: InMemoryLocalStore(),
    );

    await motor.stage('venta', Op.insert, {'id': 'v-1'}, clientOpId: 'op-1');
    await expectLater(motor.syncNow(), throwsStateError);

    expect(jobs.withState(JobState.inFlight), isEmpty,
        reason: 'un job IN_FLIGHT no lo reclama nadie: la venta nunca sube');
    expect(jobs.withState(JobState.pending), hasLength(1));

    await motor.dispose();
  });

  test('la app arranca y recupera lo que quedó en vuelo', () async {
    // La cola sobrevive al proceso; el motor no. Se simula reusando el store
    // con un motor nuevo.
    //
    // El reloj es del store y se mueve a mano porque el reclamo va por
    // antigüedad: un job "en vuelo hace un instante" es indistinguible de uno
    // que alguien está mandando ahora mismo, y no se reclama. Acá se simula lo
    // que pasa de verdad — el proceso murió y la app volvió a abrirse un rato
    // después.
    var ahora = DateTime.utc(2026, 11, 13, 8);
    final jobs = InMemoryJobStore(clock: () => ahora);

    final primerArranque = SyncEngine(
      specs: _registro(),
      transport: TransporteRoto(),
      jobs: jobs,
      store: InMemoryLocalStore(),
    );
    final id = await primerArranque.stage('venta', Op.insert, {'id': 'v-1'},
        clientOpId: 'op-1');

    // Se muere justo después del claim: deja el job IN_FLIGHT a mano, que es
    // el estado en el que lo encuentra el arranque siguiente.
    await jobs.claimPending(limit: 10);
    expect(jobs.byId(id).state, JobState.inFlight);
    await primerArranque.dispose();

    // El colportor vuelve a abrir la app media hora después.
    ahora = ahora.add(const Duration(minutes: 30));

    final transport = FakeSyncTransport();
    final segundoArranque = SyncEngine(
      specs: _registro(),
      transport: transport,
      jobs: jobs,
      store: InMemoryLocalStore(),
    );

    await segundoArranque.syncNow();

    expect(jobs.byId(id).state, JobState.done,
        reason: 'lo que quedó en vuelo tiene que volver a la cola en el '
            'arranque siguiente, o se pierde para siempre');
    expect(transport.rowsOf('venta'), hasLength(1));

    await segundoArranque.dispose();
  });

  test('reclamar no duplica: reintentar un job ya aplicado vuelve duplicate',
      () async {
    var ahora = DateTime.utc(2026, 11, 13, 8);
    final jobs = InMemoryJobStore(clock: () => ahora);
    final transport = FakeSyncTransport();

    // El push llegó y se aplicó; la app murió antes de marcar DONE.
    await transport.push(PushBatch([
      SyncJob(
        clientOpId: 'op-1',
        entity: 'venta',
        op: Op.insert,
        payload: const {'id': 'v-1'},
        createdAt: DateTime.utc(2026, 11, 13),
      )
    ]));

    final motor = SyncEngine(
      specs: _registro(),
      transport: transport,
      jobs: jobs,
      store: InMemoryLocalStore(),
    );
    final id = await motor.stage('venta', Op.insert, {'id': 'v-1'},
        clientOpId: 'op-1');
    await jobs.claimPending(limit: 10); // muere acá
    ahora = ahora.add(const Duration(minutes: 30));

    await motor.syncNow();

    expect(jobs.byId(id).state, JobState.done);
    expect(transport.rowsOf('venta'), hasLength(1),
        reason: 'una venta, no dos');
    await motor.dispose();
  });

  // La otra mitad de la garantía, y la que hace posible RF-SY07: el trabajo en
  // segundo plano corre en **otro isolate**, con su propio motor sobre la misma
  // cola. Si reclamara todo lo que está en vuelo, se llevaría puestos los jobs
  // que el primer plano está mandando en ese momento y los reenviaría en
  // paralelo. No se duplicaría ninguna venta —el `client_op_id` lo corta— pero
  // el colportor pagaría el viaje dos veces, que es lo que RR-07 cuida.
  test('un job recién tomado no se reclama: puede estar viajando', () async {
    final ahora = DateTime.utc(2026, 11, 13, 8);
    final jobs = InMemoryJobStore(clock: () => ahora);

    final enPrimerPlano = SyncEngine(
      specs: _registro(),
      transport: TransporteRoto(),
      jobs: jobs,
      store: InMemoryLocalStore(),
    );
    final id = await enPrimerPlano.stage('venta', Op.insert, {'id': 'v-1'},
        clientOpId: 'op-1');

    // El ciclo del primer plano lo tiene en la mano ahora mismo.
    await jobs.claimPending(limit: 10);

    // El isolate de segundo plano: otro motor, la misma cola, el mismo
    // instante.
    final enSegundoPlano = SyncEngine(
      specs: _registro(),
      transport: FakeSyncTransport(),
      jobs: jobs,
      store: InMemoryLocalStore(),
    );
    await enSegundoPlano.syncNow();

    expect(jobs.byId(id).state, JobState.inFlight,
        reason: 'el de segundo plano no puede robarle un job al que lo está '
            'mandando');

    await enPrimerPlano.dispose();
    await enSegundoPlano.dispose();
  });
}
