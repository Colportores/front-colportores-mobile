// `sync_meta` sobre la DB local tiene que portarse como `InMemorySyncMeta`, contra el que se
// verificó el motor: `runSyncMetaContract` es la definición ejecutable del puerto (#486).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/drift_sync_meta.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/port_contracts.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final abiertas = <AppDatabase>[];
  tearDown(() async {
    for (final db in abiertas) {
      await db.close();
    }
    abiertas.clear();
  });

  AppDatabase abrir() {
    final db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    abiertas.add(db);
    return db;
  }

  runSyncMetaContract('DriftSyncMeta', () => DriftSyncMeta(abrir()));

  test('un valor ilegible en la tabla es «no hay dato», no una excepción', () async {
    final db = abrir();
    await db.customStatement(
      "INSERT INTO sync_meta (clave, valor) VALUES ('last_pull_at', 'esto no es una fecha'), "
      "('last_push_network', 'ethernet')",
    );

    final meta = await DriftSyncMeta(db).read();

    expect(meta.lastPullAt, isNull, reason: 'la vista de estado tiene que abrir igual');
    expect(meta.lastPushNetwork, isNull);
  });

  test(
    'las fechas se guardan en ISO 8601 UTC y la red por su nombre (legible en un dump)',
    () async {
      final db = abrir();
      final meta = DriftSyncMeta(db);

      await meta.write(
        lastPullAt: DateTime.utc(2026, 10, 27, 8, 30),
        lastPushAt: DateTime.utc(2026, 10, 27, 9),
        lastPushNetwork: SyncNetwork.mobile,
      );

      final filas = await db
          .customSelect('SELECT clave, valor FROM sync_meta ORDER BY clave')
          .get();
      expect(
        {for (final f in filas) f.read<String>('clave'): f.read<String>('valor')},
        {
          'last_pull_at': '2026-10-27T08:30:00.000Z',
          'last_push_at': '2026-10-27T09:00:00.000Z',
          'last_push_network': 'mobile',
        },
      );
    },
  );

  test('una hora local se guarda en UTC y vuelve como el mismo instante', () async {
    final meta = DriftSyncMeta(abrir());
    final local = DateTime.utc(2026, 10, 27, 11).toLocal();

    await meta.write(lastBackupAt: local);

    final leida = (await meta.read()).lastBackupAt!;
    expect(leida.isAtSameMomentAs(local), isTrue);
    expect(leida.isUtc, isTrue);
  });

  test('sobrevive a reiniciar: otra conexión a la misma DB ve lo anotado', () async {
    final db = abrir();
    await DriftSyncMeta(db).write(
      lastPullAt: DateTime.utc(2026, 10, 27, 8),
      lastBackupAt: DateTime.utc(2026, 10, 27, 2, 10),
      lastPushAt: DateTime.utc(2026, 10, 27, 7, 57),
      lastPushNetwork: SyncNetwork.mobile,
    );

    // Un objeto nuevo sobre la misma DB: lo mismo que un motor nuevo tras reabrir la app.
    final despues = await DriftSyncMeta(db).read();

    expect(despues.lastPullAt, DateTime.utc(2026, 10, 27, 8));
    expect(despues.lastBackupAt, DateTime.utc(2026, 10, 27, 2, 10));
    expect(despues.lastPushNetwork, SyncNetwork.mobile);
  });

  test(
    'un motor sobre la DB real se acuerda de la bajada y de la red del envío tras reabrir',
    () async {
      final db = abrir();
      final transport = FakeSyncTransport();
      SyncEngine armar() => SyncEngine(
        specs: SpecRegistry(
          [SyncSpec.push('visita'), SyncSpec.pull('producto')],
          allEntities: {'visita', 'producto'},
        ),
        transport: transport,
        jobs: InMemoryJobStore(),
        store: InMemoryLocalStore(),
        meta: DriftSyncMeta(db),
        connectivity: FakeConnectivityPort()..goMobile(),
      );

      final motor = armar();
      await motor.stage('visita', Op.insert, {'id': 'vi-1'}, clientOpId: 'op-1');
      await motor.syncNow();
      final antes = await motor.statusNow();
      await motor.dispose();

      final reabierto = armar();
      final despues = await reabierto.statusNow();
      await reabierto.dispose();

      expect(antes.lastPullAt, isNotNull);
      expect(despues.lastPullAt, antes.lastPullAt);
      expect(despues.lastPushNetwork, SyncNetwork.mobile);
    },
  );
}
