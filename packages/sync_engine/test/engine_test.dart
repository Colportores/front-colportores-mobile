import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

const _entidades = {'venta', 'jornada', 'producto', 'ubicacion', 'persona'};

SpecRegistry _registro() => SpecRegistry([
      SyncSpec.push('venta'),
      SyncSpec.push('jornada', critical: true),
      SyncSpec.push('ubicacion', alsoPull: true),
      SyncSpec.pull('producto', realtime: true),
      SyncSpec.local('persona'),
    ], allEntities: _entidades);

({
  SyncEngine motor,
  InMemoryJobStore jobs,
  InMemoryLocalStore store,
  FakeSyncTransport transport,
  FakeConnectivityPort red,
}) _armar() {
  final jobs = InMemoryJobStore();
  final store = InMemoryLocalStore();
  final transport = FakeSyncTransport();
  final red = FakeConnectivityPort();
  return (
    motor: SyncEngine(
      specs: _registro(),
      transport: transport,
      jobs: jobs,
      store: store,
      connectivity: red,
      // Ventana corta para no hacer esperar a los tests.
      criticalDebounce: const Duration(milliseconds: 5),
    ),
    jobs: jobs,
    store: store,
    transport: transport,
    red: red,
  );
}

void main() {
  group('triggers (§5.2)', () {
    test('una escritura critical dispara el ciclo sola', () async {
      final (:motor, :transport, jobs: _, store: _, red: _) = _armar();

      await motor.stage('jornada', Op.insert, {'id': 'j1'}, clientOpId: 'op-1');
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(transport.rowsOf('jornada'), hasLength(1),
          reason: 'una jornada no espera al próximo trigger');
      await motor.dispose();
    });

    test('una ráfaga de escrituras críticas es un solo push', () async {
      final (:motor, :transport, jobs: _, store: _, red: _) = _armar();

      // Una venta con tres items: cuatro stage() seguidos, una sola operación
      // del colportor.
      for (var i = 0; i < 4; i++) {
        await motor.stage('jornada', Op.insert, {'id': 'j$i'},
            clientOpId: 'op-$i');
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(transport.batches, hasLength(1),
          reason: 'cuatro requests para una venta con items es tirar datos '
              'del colportor a la basura');
      expect(transport.rowsOf('jornada'), hasLength(4));
      await motor.dispose();
    });

    test('flush() no espera la ventana: la app pasa a segundo plano', () async {
      final (:motor, :transport, jobs: _, store: _, red: _) = _armar();

      await motor.stage('jornada', Op.insert, {'id': 'j1'}, clientOpId: 'op-1');
      await motor.flush();

      expect(transport.rowsOf('jornada'), hasLength(1));
      await motor.dispose();
    });

    test('una escritura no critical espera', () async {
      final (:motor, :transport, jobs: _, store: _, red: _) = _armar();

      await motor.stage('venta', Op.insert, {'id': 'v1'}, clientOpId: 'op-1');
      await motor.settled;

      expect(transport.rowsOf('venta'), isEmpty);
      await motor.syncNow();
      expect(transport.rowsOf('venta'), hasLength(1));
      await motor.dispose();
    });

    test('recuperar la red dispara un ciclo', () async {
      final (:motor, :transport, :red, jobs: _, store: _) = _armar();
      await motor.stage('venta', Op.insert, {'id': 'v1'}, clientOpId: 'op-1');

      red.goOffline();
      red.goOnline();
      await Future<void>.delayed(Duration.zero);
      await motor.settled;

      expect(transport.rowsOf('venta'), hasLength(1));
      await motor.dispose();
    });

    test('dos syncNow en paralelo corren en fila, no encimados', () async {
      final (:motor, :transport, jobs: _, store: _, red: _) = _armar();
      await motor.stage('venta', Op.insert, {'id': 'v1'}, clientOpId: 'op-1');

      final resultados = await Future.wait([motor.syncNow(), motor.syncNow()]);

      // Ninguno se saltea: el colportor apretó el botón dos veces y las dos
      // veces pasó algo. Pero no se pisan.
      expect(resultados.where((r) => r.skipped), isEmpty);
      expect(transport.batches, hasLength(1),
          reason: 'el segundo no encuentra nada pendiente');
      expect(transport.rowsOf('venta'), hasLength(1));
      await motor.dispose();
    });

    test('un trigger automático durante un ciclo se saltea', () async {
      final (:motor, transport: _, jobs: _, store: _, red: _) = _armar();
      await motor.stage('venta', Op.insert, {'id': 'v1'}, clientOpId: 'op-1');

      final manual = motor.syncNow();
      final automatico = await motor.trigger(SyncTrigger.appResumed);

      expect(automatico.skipped, isTrue,
          reason: 'no se encima con el que ya está corriendo');
      expect((await manual).ok, isTrue);
      await motor.dispose();
    });

    test('un trigger salteado no se pierde: corre al terminar el otro',
        () async {
      final (:motor, :transport, :jobs, store: _, red: _) = _armar();

      final manual = motor.syncNow();
      // Llega mientras el manual corre, y trae algo que el manual no vio.
      await motor.stage('venta', Op.insert, {'id': 'v-1'}, clientOpId: 'op-1');
      await motor.trigger(SyncTrigger.connectivity);
      await manual;
      await motor.settled;

      expect(transport.rowsOf('venta'), hasLength(1),
          reason: 'si vuelve la red mientras corre otra cosa, esa señal no se '
              'puede tirar: el próximo trigger puede tardar horas');
      expect(jobs.withState(JobState.pending), isEmpty);
      await motor.dispose();
    });
  });

  group('ahorro de datos (HU-SYNC-008)', () {
    test('bloquea los automáticos pero nunca el manual', () async {
      final (:motor, :transport, jobs: _, store: _, red: _) = _armar();
      await motor.stage('venta', Op.insert, {'id': 'v1'}, clientOpId: 'op-1');

      motor.setDataSaver(true);
      final auto = await motor.trigger(SyncTrigger.appResumed);
      expect(auto.skipped, isTrue);
      expect(transport.batches, isEmpty);

      final manual = await motor.syncNow();
      expect(manual.ok, isTrue);
      expect(transport.rowsOf('venta'), hasLength(1));
      await motor.dispose();
    });
  });

  group('pull (§10)', () {
    test('baja el delta de las pull y de las push con alsoPull', () async {
      final (:motor, :store, :transport, jobs: _, red: _) = _armar();
      transport
        ..seed('producto', [
          {'id': 'p1', 'nombre': 'El Camino a Cristo'}
        ])
        ..seed('ubicacion', [
          {'id': 'u1', 'calle_hash': 'abc'}
        ]);

      final r = await motor.syncNow();

      expect(r.pulled, 2);
      expect(store.rows.keys, unorderedEquals(['producto', 'ubicacion']));
      await motor.dispose();
    });

    test('nunca pide delta de una entidad local', () async {
      final (:motor, :transport, jobs: _, store: _, red: _) = _armar();
      await motor.syncNow();

      for (final pedido in transport.pulls) {
        expect(pedido.entities, isNot(contains('persona')));
      }
      await motor.dispose();
    });

    test('si aplicar la transacción falla, el watermark no avanza', () async {
      final (:motor, :store, :transport, jobs: _, red: _) = _armar();
      transport.seed('producto', [
        {'id': 'p1'}
      ]);
      store.failOnApply = true;

      await expectLater(motor.syncNow(), throwsA(isA<StateError>()));
      expect(store.watermarks, isEmpty);

      // El próximo pull vuelve a traer lo mismo.
      store.failOnApply = false;
      final r = await motor.syncNow();
      expect(r.pulled, 1);
      expect(store.rows['producto'], hasLength(1));
      await motor.dispose();
    });

    test('la segunda sync no vuelve a bajar lo que ya bajó', () async {
      final (:motor, :store, :transport, jobs: _, red: _) = _armar();
      transport.seed('producto', [
        {'id': 'p1'}
      ]);

      expect((await motor.syncNow()).pulled, 1);
      expect((await motor.syncNow()).pulled, 0);
      expect(store.applies, 1);
      await motor.dispose();
    });
  });

  group('estado y purga', () {
    test('status emite los contadores que muestra la UI (§3)', () async {
      final (:motor, :transport, jobs: _, store: _, red: _) = _armar();
      final vistos = <SyncStatus>[];
      final sub = motor.status.listen(vistos.add);

      await motor.stage('venta', Op.insert, {'id': 'v1'}, clientOpId: 'op-1');
      transport.failWith(422);
      await motor.syncNow();

      await Future<void>.delayed(Duration.zero);
      expect(vistos.first.pending, 1);
      expect(vistos.last.invalid, 1);
      expect(vistos.last.pending, 0);

      await sub.cancel();
      await motor.dispose();
    });

    test('los DONE se compactan a los 7 días (§5.8)', () async {
      var ahora = DateTime.utc(2026, 8, 28);
      final jobs = InMemoryJobStore();
      final motor = SyncEngine(
        specs: _registro(),
        transport: FakeSyncTransport(),
        jobs: jobs,
        store: InMemoryLocalStore(),
        clock: () => ahora,
      );

      await motor.stage('venta', Op.insert, {'id': 'v1'}, clientOpId: 'op-1');
      await motor.syncNow();
      expect(jobs.withState(JobState.done), hasLength(1));

      ahora = DateTime.utc(2026, 9, 1); // 4 días después
      expect(await motor.purge(), 0, reason: 'todavía no llegó a los 7');

      ahora = DateTime.utc(2026, 9, 5); // 8 días después
      expect(await motor.purge(), 1);
      expect(jobs.all, isEmpty);
      await motor.dispose();
    });
  });
}
