// HU-SYNC-007 (estado de sincronización y sync manual) y HU-SYNC-008 (ahorro de
// datos), del lado del motor. La pantalla (#174) renderiza lo que acá se fija.

import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

SpecRegistry _registro() => SpecRegistry(
  [
    SyncSpec.push('venta', critical: true),
    SyncSpec.push('visita'),
    SyncSpec.pull('producto', realtime: true),
    SyncSpec.local('persona'),
  ],
  allEntities: {'venta', 'visita', 'producto', 'persona'},
);

typedef _Banco = ({
  SyncEngine motor,
  FakeSyncTransport transport,
  InMemoryJobStore jobs,
  FakeConnectivityPort red,
  FakeRealtime rt,
});

_Banco _armar({BackupService? backup}) {
  final transport = FakeSyncTransport();
  final jobs = InMemoryJobStore();
  final red = FakeConnectivityPort();
  final rt = FakeRealtime();
  return (
    motor: SyncEngine(
      specs: _registro(),
      transport: transport,
      jobs: jobs,
      store: InMemoryLocalStore(),
      connectivity: red,
      realtime: rt,
      backup: backup,
      criticalDebounce: const Duration(milliseconds: 5),
      realtimeDebounce: const Duration(milliseconds: 5),
    ),
    transport: transport,
    jobs: jobs,
    red: red,
    rt: rt,
  );
}

Future<void> _asentar() =>
    Future<void>.delayed(const Duration(milliseconds: 40));

void main() {
  group('ahorro de datos (HU-SYNC-008)', () {
    test(
      'datos móviles: el pull periódico se pausa y deja el motivo',
      () async {
        final b = _armar();
        b.transport.seed('producto', [
          {'id': 'p-1'},
        ]);
        b.motor.setDataSaver(true);
        b.red.goMobile();

        final r = await b.motor.trigger(SyncTrigger.appResumed);

        expect(r.pausedReason, 'data_saver_on_mobile');
        expect(
          r.ok,
          isTrue,
          reason: 'pausar el pull no es una falla del ciclo',
        );
        expect(b.transport.pulls, isEmpty);
        final estado = await b.motor.statusNow();
        expect(estado.pullPausedReason, 'data_saver_on_mobile');
        expect(estado.lastPullAt, isNull);
        expect(
          estado.lastSuccessAt,
          isNull,
          reason: 'un ciclo sin pull no es un sync completo',
        );
        await b.motor.dispose();
      },
    );

    test('datos móviles: una venta sube igual, aunque haya ahorro', () async {
      final b = _armar();
      b.motor.setDataSaver(true);
      b.red.goMobile();

      await b.motor.stage('venta', Op.insert, {
        'id': 'v-1',
      }, clientOpId: 'op-1');
      await _asentar();

      expect(
        b.transport.rowsOf('venta'),
        hasLength(1),
        reason: 'lo crítico no espera al Wi-Fi',
      );
      expect(b.transport.pulls, isEmpty);
      await b.motor.dispose();
    });

    test(
      'también sube lo que no es crítico: el ahorro frena la bajada',
      () async {
        final b = _armar();
        b.motor.setDataSaver(true);
        b.red.goMobile();
        await b.motor.stage('visita', Op.insert, {
          'id': 'vi-1',
        }, clientOpId: 'op-1');

        await b.motor.trigger(SyncTrigger.connectivity);

        expect(b.transport.rowsOf('visita'), hasLength(1));
        await b.motor.dispose();
      },
    );

    test('con Wi-Fi baja como siempre', () async {
      final b = _armar();
      b.transport.seed('producto', [
        {'id': 'p-1'},
      ]);
      b.motor.setDataSaver(true);

      final r = await b.motor.trigger(SyncTrigger.appResumed);

      expect(r.pausedReason, isNull);
      expect(r.pulled, 1);
      expect((await b.motor.statusNow()).pullPausedReason, isNull);
      await b.motor.dispose();
    });

    test('sin ahorro, con datos móviles también baja', () async {
      final b = _armar();
      b.red.goMobile();

      final r = await b.motor.trigger(SyncTrigger.appResumed);

      expect(r.pausedReason, isNull);
      expect(b.transport.pulls, isNotEmpty);
      await b.motor.dispose();
    });

    test('el sync manual baja siempre, también con datos móviles', () async {
      final b = _armar();
      b.transport.seed('producto', [
        {'id': 'p-1'},
      ]);
      b.motor.setDataSaver(true);
      b.red.goMobile();

      final r = await b.motor.syncNow();

      expect(r.pausedReason, isNull);
      expect(r.pulled, 1);
      final estado = await b.motor.statusNow();
      expect(estado.lastPullAt, isNotNull);
      expect(estado.lastSuccessAt, isNotNull);
      await b.motor.dispose();
    });

    test('realtime sigue activo con datos móviles (es liviano)', () async {
      final b = _armar();
      b.transport.seed('producto', [
        {'id': 'p-1'},
      ]);
      b.motor.setDataSaver(true);
      b.red.goMobile();

      b.rt.emit('producto');
      await _asentar();

      expect(b.transport.pulls, isNotEmpty);
      await b.motor.dispose();
    });

    test('al aparecer un Wi-Fi sale el pull que quedó esperando', () async {
      final b = _armar();
      b.transport.seed('producto', [
        {'id': 'p-1'},
      ]);
      b.motor.setDataSaver(true);
      b.red.goMobile();
      await b.motor.trigger(SyncTrigger.appResumed);
      expect(b.transport.pulls, isEmpty);

      b.red.goWifi();
      await _asentar();

      expect(
        b.transport.pulls,
        isNotEmpty,
        reason:
            'pasar de datos móviles a Wi-Fi no cambia «online», pero es '
            'justo lo que el ahorro estaba esperando',
      );
      expect((await b.motor.statusNow()).pullPausedReason, isNull);
      await b.motor.dispose();
    });

    test(
      'un Wi-Fi que aparece sin nada en pausa no dispara un ciclo',
      () async {
        final b = _armar();
        b.motor.setDataSaver(true);
        b.red.goMobile();

        b.red.goWifi();
        await _asentar();

        expect(b.transport.pulls, isEmpty);
        await b.motor.dispose();
      },
    );

    test('sin red no se culpa al ahorro: el pull falla como siempre', () async {
      final b = _armar();
      b.motor.setDataSaver(true);
      b.red.goOffline();
      b.transport.offline();

      final r = await b.motor.trigger(SyncTrigger.appResumed);

      expect(r.pausedReason, isNull);
      expect(r.failure, isNotNull);
      await b.motor.dispose();
    });

    test('apagar el ahorro limpia el motivo del estado', () async {
      final b = _armar();
      b.motor.setDataSaver(true);
      b.red.goMobile();
      await b.motor.trigger(SyncTrigger.appResumed);
      expect((await b.motor.statusNow()).pullPausedReason, isNotNull);

      b.motor.setDataSaver(false);

      final estado = await b.motor.statusNow();
      expect(estado.pullPausedReason, isNull);
      expect(estado.dataSaver, isFalse);
      expect(b.motor.dataSaver, isFalse);
      await b.motor.dispose();
    });

    test('el estado emite el cambio de modo', () async {
      final b = _armar();
      final vistos = <SyncStatus>[];
      final sub = b.motor.status.listen(vistos.add);

      b.motor.setDataSaver(true);
      await _asentar();

      expect(vistos.last.dataSaver, isTrue);
      await sub.cancel();
      await b.motor.dispose();
    });

    test('el backup automático pide Wi-Fi solo con el ahorro activo', () async {
      final b = _armar();
      b.red.goMobile();
      expect(
        await b.motor.automaticBackupAllowed(),
        isTrue,
        reason: 'sin ahorro, el comportamiento es el de siempre',
      );

      b.motor.setDataSaver(true);
      expect(await b.motor.automaticBackupAllowed(), isFalse);

      b.red.goWifi();
      expect(await b.motor.automaticBackupAllowed(), isTrue);
      await b.motor.dispose();
    });

    test(
      'sin puerto de conectividad no hay forma de saber: se asume Wi-Fi',
      () async {
        final transport = FakeSyncTransport();
        final motor = SyncEngine(
          specs: _registro(),
          transport: transport,
          jobs: InMemoryJobStore(),
          store: InMemoryLocalStore(),
        )..setDataSaver(true);

        final r = await motor.trigger(SyncTrigger.appResumed);

        expect(r.pausedReason, isNull);
        expect(await motor.automaticBackupAllowed(), isTrue);
        await motor.dispose();
      },
    );
  });

  group('estado de sincronización (HU-SYNC-007)', () {
    test('el estado de ahora no espera a que pase algo', () async {
      final b = _armar();
      await b.motor.stage('visita', Op.insert, {
        'id': 'vi-1',
      }, clientOpId: 'op-1');

      final estado = await b.motor.statusNow();

      expect(estado.pending, 1);
      expect(estado.invalid, 0);
      expect(estado.lastPushAt, isNull);
      expect(estado.lastPullAt, isNull);
      expect(estado.lastBackupAt, isNull);
      await b.motor.dispose();
    });

    test('forzar un sync sube, baja y deja los contadores en cero', () async {
      final b = _armar();
      b.transport.seed('producto', [
        {'id': 'p-1'},
      ]);
      for (var i = 0; i < 5; i++) {
        await b.motor.stage('visita', Op.insert, {
          'id': 'vi-$i',
        }, clientOpId: 'op-$i');
      }
      expect((await b.motor.statusNow()).pending, 5);

      final r = await b.motor.syncNow();

      expect(r.pushed, 5);
      expect(r.pulled, 1);
      final estado = await b.motor.statusNow();
      expect(estado.pending, 0);
      expect(estado.lastPushAt, isNotNull);
      expect(estado.lastPullAt, isNotNull);
      expect(estado.lastSuccessAt, isNotNull);
      await b.motor.dispose();
    });

    test(
      'la última subida sale de la cola: sobrevive a un motor nuevo',
      () async {
        final b = _armar();
        await b.motor.stage('visita', Op.insert, {
          'id': 'vi-1',
        }, clientOpId: 'op-1');
        await b.motor.syncNow();
        await b.motor.dispose();

        // La app se cerró y se volvió a abrir: mismo teléfono, motor nuevo.
        final reabierto = SyncEngine(
          specs: _registro(),
          transport: b.transport,
          jobs: b.jobs,
          store: InMemoryLocalStore(),
        );

        expect((await reabierto.statusNow()).lastPushAt, isNotNull);
        await reabierto.dispose();
      },
    );

    test('un ciclo que falla no mueve las fechas', () async {
      final b = _armar();
      await b.motor.stage('visita', Op.insert, {
        'id': 'vi-1',
      }, clientOpId: 'op-1');
      b.transport.offline();

      await b.motor.syncNow();

      final estado = await b.motor.statusNow();
      expect(estado.pending, 1);
      expect(estado.lastPushAt, isNull);
      expect(estado.lastPullAt, isNull);
      await b.motor.dispose();
    });

    test('el último backup lo informa el servicio de backup', () async {
      final backup = BackupService(
        archive: FakeArchive(authorized: true),
        crypto: FakeCrypto(),
        snapshot: FakeSnapshot(),
      );
      final b = _armar(backup: backup);
      final vistos = <SyncStatus>[];
      final sub = b.motor.status.listen(vistos.add);

      final entrada = await b.motor.backup.backupNow(watermark: 'w-1');
      await _asentar();

      expect((await b.motor.statusNow()).lastBackupAt, entrada.createdAt);
      expect(vistos.last.lastBackupAt, entrada.createdAt);
      await sub.cancel();
      await b.motor.dispose();
    });

    test(
      'un contador de pantalla que falla no deshace un backup hecho',
      () async {
        final drive = FakeArchive(authorized: true);
        final backup = BackupService(
          archive: drive,
          crypto: FakeCrypto(),
          snapshot: FakeSnapshot(),
        )..alTerminarUnBackup = (_) async => throw StateError('no importa');

        final entrada = await backup.backupNow(watermark: 'w-1');

        expect(entrada.isBase, isTrue);
        expect(drive.entries, hasLength(1));
      },
    );
  });

  group('operaciones fallidas (HU-SYNC-007, «Ver detalle»)', () {
    Future<_Banco> conUnaFallida() async {
      final b = _armar();
      await b.motor.stage('visita', Op.insert, {
        'id': 'vi-1',
        'nota': 'Ana',
      }, clientOpId: 'op-mala');
      b.transport.rejectJob(
        'op-mala',
        '23505',
        'Key (email)=(ana@correo.com) already exists.',
      );
      await b.motor.syncNow();
      return b;
    }

    test('trae tabla, tipo, fecha y último error, sin el payload', () async {
      final b = await conUnaFallida();

      final fallidas = await b.motor.failedOperations();

      expect(fallidas, hasLength(1));
      final f = fallidas.single;
      expect(f.entity, 'visita');
      expect(f.op, Op.insert);
      expect(f.code, '23505');
      expect(
        f.lastError,
        isNot(contains('ana@correo.com')),
        reason: 'el mensaje del servidor cita el valor: es un dato personal',
      );
      expect(f.lastError, contains('already exists'));
      await b.motor.dispose();
    });

    test('el id que trae es el que acepta requeue()', () async {
      final b = await conUnaFallida();
      final id = (await b.motor.failedOperations()).single.jobId;

      await b.motor.requeue(id);

      expect((await b.motor.statusNow()).invalid, 0);
      expect((await b.motor.statusNow()).pending, 1);
      await b.motor.dispose();
    });

    test('«Reintentar todas» reencola todas y no pierde ninguna', () async {
      final b = _armar();
      for (var i = 0; i < 3; i++) {
        await b.motor.stage('visita', Op.insert, {
          'id': 'vi-$i',
        }, clientOpId: 'op-$i');
        b.transport.rejectJob('op-$i', 'FILA_INEXISTENTE');
      }
      await b.motor.syncNow();
      expect((await b.motor.statusNow()).invalid, 3);

      final n = await b.motor.requeueAllInvalid();

      expect(n, 3);
      final estado = await b.motor.statusNow();
      expect(estado.invalid, 0);
      expect(estado.pending, 3);

      // Corregido el problema del lado del servidor, el reintento las sube.
      b.transport.clearRejections();
      await b.motor.syncNow();
      expect(b.transport.rowsOf('visita'), hasLength(3));
      await b.motor.dispose();
    });

    test('«Reintentar todas» sin fallidas no hace nada', () async {
      final b = _armar();
      expect(await b.motor.requeueAllInvalid(), 0);
      await b.motor.dispose();
    });

    test(
      'si el servidor las rechaza otra vez, vuelven a la cola de error',
      () async {
        final b = await conUnaFallida();

        await b.motor.requeueAllInvalid();
        await b.motor.syncNow();

        expect((await b.motor.statusNow()).invalid, 1);
        await b.motor.dispose();
      },
    );
  });

  group('sanitizarError', () {
    test('saca los valores que cita el servidor', () {
      expect(
        sanitizarError('Key (email)=(a@b.com) already exists.'),
        'Key (…)=(…) already exists.',
      );
      expect(
        sanitizarError('invalid input syntax for type date: "Juan Pérez"'),
        'invalid input syntax for type date: «…»',
      );
      expect(sanitizarError("value: 'x'"), 'value: «…»');
    });

    test('saca correos sueltos y números largos', () {
      expect(
        sanitizarError('no se pudo avisar a ana@correo.com'),
        'no se pudo avisar a …',
      );
      expect(
        sanitizarError('documento 12345678 repetido'),
        'documento … repetido',
      );
    });

    test('deja intacto un mensaje sin datos', () {
      expect(sanitizarError('FILA_INEXISTENTE'), 'FILA_INEXISTENTE');
      expect(sanitizarError(''), '');
    });

    test('corta lo muy largo', () {
      final s = sanitizarError('x' * 500);
      expect(s.length, 201);
      expect(s, endsWith('…'));
    });
  });
}
