// HU-SYNC-007, seguimiento (#486): el motor se acuerda, entre una apertura de la app y la
// siguiente, de cuándo bajó el delta, cuándo hizo el último respaldo y por qué red salió el
// último envío. La vista 25 muestra «Última actualización», «Último respaldo» y «· por datos».

import 'package:sync_engine/port_contracts.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

SpecRegistry _registro() => SpecRegistry(
  [
    SyncSpec.push('visita'),
    SyncSpec.pull('producto', realtime: true),
  ],
  allEntities: {'visita', 'producto'},
);

typedef _Telefono = ({
  InMemoryJobStore jobs,
  InMemoryLocalStore store,
  InMemorySyncMeta meta,
  FakeSyncTransport transport,
  FakeConnectivityPort red,
});

/// El teléfono: la DB (cola, réplica y meta) que sobrevive a cerrar la app.
_Telefono _telefono() => (
  jobs: InMemoryJobStore(),
  store: InMemoryLocalStore(),
  meta: InMemorySyncMeta(),
  transport: FakeSyncTransport(),
  red: FakeConnectivityPort(),
);

/// Abre la app: un motor nuevo sobre el mismo teléfono.
SyncEngine _abrir(
  _Telefono t, {
  BackupService? backup,
  bool conRed = true,
  bool conMeta = true,
  DateTime Function()? clock,
}) => SyncEngine(
  specs: _registro(),
  transport: t.transport,
  jobs: t.jobs,
  store: t.store,
  meta: conMeta ? t.meta : null,
  connectivity: conRed ? t.red : null,
  backup: backup,
  clock: clock,
);

Future<void> _encolar(SyncEngine motor, String id) =>
    motor.stage('visita', Op.insert, {'id': id}, clientOpId: 'op-$id');

void main() {
  runSyncMetaContract('InMemorySyncMeta', InMemorySyncMeta.new);

  group('última actualización y último respaldo sobreviven a reiniciar', () {
    test('la bajada anotada se ve en un motor nuevo, antes de cualquier ciclo', () async {
      final t = _telefono();
      final motor = _abrir(t);
      t.transport.seed('producto', [
        {'id': 'p-1'},
      ]);
      await motor.syncNow();
      final bajo = (await motor.statusNow()).lastPullAt;
      expect(bajo, isNotNull);
      await motor.dispose();

      // El celular se reinició: motor nuevo, sin ciclo todavía.
      final reabierto = _abrir(t);
      final estado = await reabierto.statusNow();

      expect(estado.lastPullAt, bajo, reason: 'no puede decir «Todavía no hubo»');
      expect(estado.lastSuccessAt, isNull, reason: 'eso sigue siendo de este arranque');
      await reabierto.dispose();
    });

    test('el respaldo anotado se ve en un motor nuevo', () async {
      final t = _telefono();
      final backup = BackupService(
        archive: FakeArchive(authorized: true),
        crypto: FakeCrypto(),
        snapshot: FakeSnapshot(),
      );
      final motor = _abrir(t, backup: backup);
      final entrada = await motor.backup.backupNow(watermark: 'w-1');
      await motor.dispose();

      final reabierto = _abrir(t);

      expect((await reabierto.statusNow()).lastBackupAt, entrada.createdAt);
      await reabierto.dispose();
    });

    test('el backup guarda el watermark de pull que tiene el motor (§7, fase 3)', () async {
      final t = _telefono();
      final archivo = FakeArchive(authorized: true);
      final backup = BackupService(
        archive: archivo,
        crypto: FakeCrypto(),
        snapshot: FakeSnapshot(),
      );
      final motor = _abrir(t, backup: backup);
      await t.store.applyDelta(const {}, scope: 'mirror', watermark: 'wm-7');

      final entrada = await motor.backup.backupNow();

      expect(entrada.watermark, 'wm-7', reason: 'el restore arranca la reconciliación desde acá');
      await motor.dispose();
      expect(backup.watermarkProvider, isNull, reason: 'cerrado el motor no queda colgado');
    });

    test('instalación nueva: no hay nada anotado y el estado lo dice con null', () async {
      final t = _telefono();
      final motor = _abrir(t);

      final estado = await motor.statusNow();

      expect(estado.lastPullAt, isNull);
      expect(estado.lastBackupAt, isNull);
      expect(estado.lastPushAt, isNull);
      expect(estado.lastPushNetwork, isNull);
      await motor.dispose();
    });

    test('un ciclo que falla no mueve lo anotado', () async {
      final t = _telefono();
      final motor = _abrir(t);
      t.transport.seed('producto', [
        {'id': 'p-1'},
      ]);
      await motor.syncNow();
      final antes = (await t.meta.read()).lastPullAt;

      t.transport.offline();
      await _encolar(motor, 'vi-1');
      await motor.syncNow();

      expect((await t.meta.read()).lastPullAt, antes);
      expect((await motor.statusNow()).lastPullAt, antes);
      await motor.dispose();
    });

    test('una bajada pausada por el ahorro de datos no anota nada', () async {
      final t = _telefono();
      final motor = _abrir(t)..setDataSaver(true);
      t.red.goMobile();

      final r = await motor.trigger(SyncTrigger.appResumed);

      expect(r.pausedReason, kDataSaverOnMobile);
      expect((await t.meta.read()).lastPullAt, isNull);
      await motor.dispose();
    });

    test('si la DB falla al anotar, el ciclo termina bien y el dato queda en memoria', () async {
      final t = _telefono();
      final motor = _abrir(t);
      t.meta.failOnWrite = true;
      await _encolar(motor, 'vi-1');

      final r = await motor.syncNow();

      expect(r.ok, isTrue, reason: 'una bajada hecha no se deshace por un contador');
      expect(r.pushed, 1);
      final estado = await motor.statusNow();
      expect(estado.lastPullAt, isNotNull);
      expect(estado.lastPushAt, isNotNull);
      await motor.dispose();
    });

    test('si la DB falla al leer, el estado sale de la memoria del motor', () async {
      final t = _telefono();
      final motor = _abrir(
        t,
      );
      final roto = SyncEngine(
        specs: _registro(),
        transport: t.transport,
        jobs: t.jobs,
        store: t.store,
        meta: _MetaQueNoLee(),
      );
      await roto.syncNow();

      final estado = await roto.statusNow();

      expect(estado.lastPullAt, isNotNull);
      await roto.dispose();
      await motor.dispose();
    });

    test('el dato guardado más nuevo gana (otro isolate pudo bajar después)', () async {
      final t = _telefono();
      final motor = _abrir(t);
      await motor.syncNow();
      final propio = (await motor.statusNow()).lastPullAt!;
      final ajeno = propio.add(const Duration(minutes: 10));

      await t.meta.write(lastPullAt: ajeno);

      expect((await motor.statusNow()).lastPullAt, ajeno);
      await motor.dispose();
    });

    test('dos ciclos seguidos dejan anotada la bajada del último', () async {
      final t = _telefono();
      var ahora = DateTime.utc(2026, 10, 27, 8);
      final motor = _abrir(t, clock: () => ahora);
      await motor.syncNow();
      ahora = ahora.add(const Duration(hours: 3));
      await motor.syncNow();

      expect((await t.meta.read()).lastPullAt, DateTime.utc(2026, 10, 27, 11));
      await motor.dispose();
    });

    test('recuperar un dispositivo anota la bajada de la reconciliación', () async {
      final t = _telefono();
      final motor = _abrir(t);

      await motor.recover();

      expect((await t.meta.read()).lastPullAt, isNotNull);
      await motor.dispose();
    });
  });

  group('red del último envío', () {
    test('por Wi-Fi: lo dice el estado y sobrevive a reiniciar', () async {
      final t = _telefono();
      final motor = _abrir(t);
      await _encolar(motor, 'vi-1');

      await motor.syncNow();

      expect((await motor.statusNow()).lastPushNetwork, SyncNetwork.wifi);
      await motor.dispose();
      final reabierto = _abrir(t);
      expect((await reabierto.statusNow()).lastPushNetwork, SyncNetwork.wifi);
      await reabierto.dispose();
    });

    test('por datos móviles: «por datos», también después de reiniciar', () async {
      final t = _telefono();
      t.red.goMobile();
      final motor = _abrir(t);
      await _encolar(motor, 'vi-1');

      await motor.syncNow();

      final estado = await motor.statusNow();
      expect(estado.pending, 0);
      expect(estado.lastPushNetwork, SyncNetwork.mobile);
      await motor.dispose();
      final reabierto = _abrir(t);
      final despues = await reabierto.statusNow();
      expect(despues.lastPushNetwork, SyncNetwork.mobile);
      expect(despues.lastPushAt, estado.lastPushAt);
      await reabierto.dispose();
    });

    test('el estado que emite el flujo también la lleva', () async {
      final t = _telefono();
      t.red.goMobile();
      final motor = _abrir(t);
      final vistos = <SyncStatus>[];
      final sub = motor.status.listen(vistos.add);
      await _encolar(motor, 'vi-1');

      await motor.syncNow();
      await pumpEventQueue();

      expect(vistos.last.lastPushNetwork, SyncNetwork.mobile);
      await sub.cancel();
      await motor.dispose();
    });

    test('se anota la del último envío, no la del primero', () async {
      final t = _telefono();
      var ahora = DateTime.utc(2026, 10, 27, 8);
      final motor = _abrir(t, clock: () => ahora);
      t.red.goMobile();
      await _encolar(motor, 'vi-1');
      await motor.syncNow();

      ahora = ahora.add(const Duration(minutes: 30));
      t.red.goWifi();
      await _encolar(motor, 'vi-2');
      await motor.syncNow();

      expect((await motor.statusNow()).lastPushNetwork, SyncNetwork.wifi);
      expect((await t.meta.read()).lastPushNetwork, SyncNetwork.wifi);
      await motor.dispose();
    });

    test('un ciclo sin nada para subir no cambia la red anotada', () async {
      final t = _telefono();
      t.red.goMobile();
      final motor = _abrir(t);
      await _encolar(motor, 'vi-1');
      await motor.syncNow();

      t.red.goWifi();
      await motor.syncNow();

      expect((await motor.statusNow()).lastPushNetwork, SyncNetwork.mobile);
      await motor.dispose();
    });

    test('un envío que falla no anota red', () async {
      final t = _telefono();
      t.red.goMobile();
      final motor = _abrir(t);
      t.transport.offline();
      await _encolar(motor, 'vi-1');

      await motor.syncNow();

      final estado = await motor.statusNow();
      expect(estado.lastPushAt, isNull);
      expect(estado.lastPushNetwork, isNull);
      await motor.dispose();
    });

    test('sin puerto de conectividad no se sabe: null, nunca un Wi-Fi inventado', () async {
      final t = _telefono();
      final motor = _abrir(t, conRed: false);
      await _encolar(motor, 'vi-1');

      await motor.syncNow();

      final estado = await motor.statusNow();
      expect(estado.lastPushAt, isNotNull);
      expect(estado.lastPushNetwork, isNull);
      await motor.dispose();
    });

    test('si el puerto de red falla, el envío sale igual y la red queda sin saber', () async {
      final t = _telefono();
      final motor = SyncEngine(
        specs: _registro(),
        transport: t.transport,
        jobs: t.jobs,
        store: t.store,
        meta: t.meta,
        connectivity: _RedQueFalla(),
      );
      await _encolar(motor, 'vi-1');

      final r = await motor.syncNow();

      expect(r.pushed, 1);
      expect((await motor.statusNow()).lastPushNetwork, isNull);
      await motor.dispose();
    });

    test('un envío de antes de anotar la red (solo en la cola) no hereda una red ajena', () async {
      final t = _telefono();
      // Un envío viejo, ya cerrado en la cola, sin red anotada.
      final id = await t.jobs.append(
        SyncJob(
          clientOpId: 'op-viejo',
          entity: 'visita',
          op: Op.insert,
          payload: const {'id': 'vi-viejo'},
          createdAt: DateTime.utc(2026, 10, 1),
        ),
      );
      await t.jobs.claimPending(limit: 10);
      await t.jobs.markDone([id], at: DateTime.utc(2026, 10, 2));
      final motor = _abrir(t);

      final estado = await motor.statusNow();

      expect(estado.lastPushAt, DateTime.utc(2026, 10, 2));
      expect(estado.lastPushNetwork, isNull);
      await motor.dispose();
    });

    test('si hay un envío más nuevo en la cola que el anotado, la red anotada no vale', () async {
      final t = _telefono();
      await t.meta.write(
        lastPushAt: DateTime.utc(2026, 10, 1),
        lastPushNetwork: SyncNetwork.mobile,
      );
      final id = await t.jobs.append(
        SyncJob(
          clientOpId: 'op-nuevo',
          entity: 'visita',
          op: Op.insert,
          payload: const {'id': 'vi-nuevo'},
          createdAt: DateTime.utc(2026, 10, 3),
        ),
      );
      await t.jobs.claimPending(limit: 10);
      await t.jobs.markDone([id], at: DateTime.utc(2026, 10, 4));
      final motor = _abrir(t);

      final estado = await motor.statusNow();

      expect(estado.lastPushAt, DateTime.utc(2026, 10, 4));
      expect(estado.lastPushNetwork, isNull);
      await motor.dispose();
    });

    test('sin SyncMetaPort el motor sigue como antes: todo en memoria', () async {
      final t = _telefono();
      final motor = _abrir(t, conMeta: false);
      await _encolar(motor, 'vi-1');

      await motor.syncNow();

      final estado = await motor.statusNow();
      expect(estado.lastPullAt, isNotNull);
      expect(estado.lastPushNetwork, SyncNetwork.wifi);
      await motor.dispose();
      expect(t.meta.writes, 0);
    });
  });

  group('SyncMeta y SyncNetwork', () {
    test('la red se guarda y se lee por su nombre', () {
      for (final red in SyncNetwork.values) {
        expect(SyncNetwork.fromWire(red.wire), red);
      }
      expect(SyncNetwork.fromWire('ethernet'), isNull);
      expect(SyncNetwork.fromWire(null), isNull);
    });

    test('toString del estado nombra la red del envío', () {
      const estado = SyncStatus(lastPushNetwork: SyncNetwork.mobile);

      expect('$estado', contains('mobile'));
    });
  });
}

/// Un `SyncMetaPort` cuya lectura falla (la DB local cerrada o rota).
class _MetaQueNoLee implements SyncMetaPort {
  @override
  Future<SyncMeta> read() async => throw StateError('no se puede leer');

  @override
  Future<void> write({
    DateTime? lastPullAt,
    DateTime? lastBackupAt,
    DateTime? lastPushAt,
    SyncNetwork? lastPushNetwork,
  }) async {}
}

/// Una conectividad cuyo plugin lanza.
class _RedQueFalla implements ConnectivityPort {
  @override
  Stream<bool> get onlineChanges => const Stream.empty();

  @override
  Future<bool> get isOnline async => throw StateError('plugin roto');

  @override
  Future<bool> get isOnWifi async => throw StateError('plugin roto');

  @override
  Stream<bool> get wifiChanges => const Stream.empty();
}
