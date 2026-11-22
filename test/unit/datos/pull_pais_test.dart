// `pais`, réplica `pull` del catálogo (contrato-sync-engine §2; decisión del 12/11 sobre P1 de #181):
// el motor la baja como `ciudad`, con el código real de los dos lados (servidor falso del paquete y
// `DriftLocalStore` sobre la DB de la app).
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../helpers/logger_mudo.dart';

Map<String, Object?> _uruguay({int version = 1, String? bajaEn, String nombre = 'Uruguay'}) => {
  'id': 'pai-uy',
  'nombre': nombre,
  'iso_code': 'UY',
  'created_at': '2026-09-01T12:00:00+00:00',
  'updated_at': '2026-09-01T12:00:00+00:00',
  'created_by': null,
  'deleted_at': bajaEn,
  'sync_version': version,
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late FakeSyncTransport servidor;
  late FakeConnectivityPort red;
  late SyncEngine motor;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    servidor = FakeSyncTransport();
    red = FakeConnectivityPort();
    motor = SyncEngine(
      specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
      transport: servidor,
      jobs: DriftJobStore(db),
      store: DriftLocalStore(db, entidades: entidadesQueEscribeElMotor),
      connectivity: red,
    );
  });
  tearDown(() async {
    await motor.dispose();
    await red.dispose();
    await db.close();
  });

  test('pais es una réplica pull, como ciudad: la app nunca la escribe', () {
    final spec = specsDeLaApp.singleWhere((s) => s.entity == 'pais');
    expect(spec.policy, SyncPolicy.pull);
    expect(entidadesQueEscribeElMotor, contains('pais'));
    expect(entidadesDelBackup, isNot(contains('pais')), reason: 'se reconstruye con el pull');
  });

  test('dado Uruguay en el servidor, cuando sincroniza, baja con su código ISO', () async {
    servidor.seed('pais', [_uruguay()]);

    final r = await motor.syncNow();

    expect(r.ok, isTrue);
    final fila = await db.select(db.paises).getSingle();
    expect(fila.id, 'pai-uy');
    expect(fila.nombre, 'Uruguay');
    expect(fila.isoCode, 'UY');
    expect(fila.deletedAt, isNull);
    expect(fila.syncVersion, 1);
  });

  test('dado un cambio en el servidor, cuando vuelve a sincronizar, pisa la fila (LWW)', () async {
    servidor.seed('pais', [_uruguay()]);
    await motor.syncNow();

    servidor.seed('pais', [_uruguay(version: 2, nombre: 'República Oriental del Uruguay')]);
    await motor.syncNow();

    final fila = await db.select(db.paises).getSingle();
    expect(fila.nombre, 'República Oriental del Uruguay');
    expect(fila.syncVersion, 2);
  });

  test(
    'dada una baja en el servidor, cuando sincroniza, la fila queda con su baja y no se borra',
    () async {
      servidor.seed('pais', [_uruguay()]);
      await motor.syncNow();

      servidor.seed('pais', [_uruguay(version: 2, bajaEn: '2026-11-12T12:00:00+00:00')]);
      await motor.syncNow();

      final fila = await db.select(db.paises).getSingle();
      expect(fila.deletedAt, isNotNull);
    },
  );
}
