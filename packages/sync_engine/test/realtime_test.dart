// §5.6 — evento → GET delta por REST → aplica a la DB local.

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

const _entidades = {
  'venta',
  'producto',
  'precio_por_zona',
  'campania',
  'persona'
};

SpecRegistry _registro() => SpecRegistry([
      SyncSpec.push('venta'),
      SyncSpec.pull('producto', realtime: true),
      SyncSpec.pull('precio_por_zona', realtime: true),
      SyncSpec.pull('campania'), // sin realtime: se actualiza en el ciclo batch
      SyncSpec.local('persona'),
    ], allEntities: _entidades);

({
  SyncEngine motor,
  FakeSyncTransport transport,
  InMemoryLocalStore store,
  FakeRealtime rt,
}) _armar() {
  final transport = FakeSyncTransport();
  final store = InMemoryLocalStore();
  final rt = FakeRealtime();
  return (
    motor: SyncEngine(
      specs: _registro(),
      transport: transport,
      jobs: InMemoryJobStore(),
      store: store,
      realtime: rt,
      // Ventana corta para no hacer esperar a los tests.
      realtimeDebounce: const Duration(milliseconds: 5),
    ),
    transport: transport,
    store: store,
    rt: rt,
  );
}

/// Espera a que pase la ventana de coalescencia y corra el ciclo.
Future<void> _asentar() async {
  await Future<void>.delayed(const Duration(milliseconds: 30));
}

void main() {
  test('se suscribe solo a las entidades con realtime: true', () async {
    final (:motor, :rt, transport: _, store: _) = _armar();

    expect(rt.subscriptions.single,
        unorderedEquals(['producto', 'precio_por_zona']));
    expect(rt.subscriptions.single, isNot(contains('campania')));
    expect(rt.subscriptions.single, isNot(contains('persona')),
        reason: 'una entidad local no existe en el servidor');

    await motor.dispose();
  });

  test('un evento baja el delta y lo aplica', () async {
    final (:motor, :rt, :transport, :store) = _armar();
    transport.seed('precio_por_zona', [
      {'id': 'pz-1', 'precio': '575.00'}
    ]);

    rt.emit('precio_por_zona');
    await _asentar();

    expect(store.rows['precio_por_zona']!.single['precio'], '575.00',
        reason: 'los Streams de Drift refrescan la UI sin código de la app');
    await motor.dispose();
  });

  test('el evento no sube la cola: solo baja', () async {
    final (:motor, :rt, :transport, store: _) = _armar();
    await motor.stage('venta', Op.insert, {'id': 'v1'}, clientOpId: 'op-1');

    rt.emit('producto');
    await _asentar();

    expect(transport.batches, isEmpty,
        reason: 'un cambio de precio del administrador no puede convertirse '
            'en tráfico de subida desde todos los celulares a la vez');
    expect(transport.pulls, isNotEmpty);
    await motor.dispose();
  });

  test('un burst de eventos se colapsa en un solo pull', () async {
    final (:motor, :rt, :transport, store: _) = _armar();
    transport.seed('producto', [
      {'id': 'p-1'}
    ]);

    for (var i = 0; i < 50; i++) {
      rt.emit('producto');
    }
    await _asentar();

    expect(transport.pulls, hasLength(1),
        reason: '50 cambios seguidos son un pull, no 50');
    await motor.dispose();
  });

  test('el ahorro de datos también frena el pull de realtime', () async {
    final (:motor, :rt, :transport, store: _) = _armar();
    motor.setDataSaver(true);

    rt.emit('producto');
    await _asentar();
    expect(transport.pulls, isEmpty);

    // Y al apagarlo, el cambio no se perdió: entra en el próximo ciclo.
    motor.setDataSaver(false);
    transport.seed('producto', [
      {'id': 'p-1'}
    ]);
    await motor.syncNow();
    expect(transport.pulls, isNotEmpty);

    await motor.dispose();
  });

  test('recover() vuelve a suscribirse en el dispositivo nuevo (§7 fase 4)',
      () async {
    final (:motor, :rt, transport: _, store: _) = _armar();
    expect(rt.subscriptions, hasLength(1));

    await motor.recover();

    expect(rt.subscriptions, hasLength(2),
        reason: 'la fase 4 repuebla los catálogos y resuscribe');
    await motor.dispose();
  });

  test('dispose corta la suscripción', () async {
    final (:motor, :rt, transport: _, store: _) = _armar();
    await motor.dispose();
    expect(rt.subscribed, isFalse);
  });
}
