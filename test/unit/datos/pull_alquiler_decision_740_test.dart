// HU-CTA-007 de punta a punta (#740, backend-supabase 0201), con el código real de los dos lados de la
// frontera: el motor baja el delta de un servidor falso que pagina y se cae como el de verdad, y lo que
// baja entra por `DriftLocalStore` a la DB de la app. `alquiler_decision` es una réplica de solo bajada: el
// pull la llena y nada del teléfono la encola. Con la fila que baja, «Mi alquiler» arma la campaña de la
// baja.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/features/cuenta/data/datasources/alquiler_local_data_source_drift.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../helpers/logger_mudo.dart';

/// La fila como la sirve el pull del servidor (backend-supabase 0201): trae también `decidido_por` y
/// `xmin_w`, que la tabla local no guarda y el motor ignora.
Map<String, Object?> _decision(
  String id, {
  String decision = 'A_CUENTA_PROXIMO_DEPOSITO',
  int monto = 500000,
  int version = 1,
  String? baja,
}) => {
  'id': id,
  'usuario_id': 'col-1',
  'campania_id': 'c-1',
  'decision': decision,
  'monto': monto,
  'decidido_por': 'coord-1',
  'decidido_en': '2026-11-12T15:00:00+00:00',
  'created_at': '2026-11-12T15:00:01+00:00',
  'updated_at': '2026-11-12T15:00:01+00:00',
  'created_by': 'coord-1',
  'deleted_at': baja,
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

  test('la entidad es de solo bajada: el contrato la declara `pull`', () {
    final spec = specsDeLaApp.singleWhere((s) => s.entity == 'alquiler_decision');

    expect(spec.policy, SyncPolicy.pull);
    expect(entidadesQueEscribeElMotor, contains('alquiler_decision'));
    // Se vuelve a bajar entera del servidor: no entra al backup.
    expect(entidadesDelBackup, isNot(contains('alquiler_decision')));
  });

  test('primera carga: baja la decisión, con sus fechas y sin lo que la tabla no guarda', () async {
    servidor.seed('alquiler_decision', [_decision('ad-1')]);

    final r = await motor.syncNow();

    expect(r.ok, isTrue);
    expect(r.pulled, 1);
    final fila = await db.select(db.alquilerDecisiones).getSingle();
    expect(fila.usuarioId, 'col-1');
    expect(fila.campaniaId, 'c-1');
    expect(fila.decision, 'A_CUENTA_PROXIMO_DEPOSITO');
    expect(fila.monto, 500000);
    expect(fila.decididoEn, DateTime.utc(2026, 11, 12, 15));
    expect(fila.createdAt, DateTime.utc(2026, 11, 12, 15, 0, 1));
    expect(fila.deletedAt, isNull);
    expect(fila.syncVersion, 1);
  });

  test('el pull no encola nada: la decisión no sube nunca', () async {
    servidor.seed('alquiler_decision', [_decision('ad-1')]);

    await motor.syncNow();

    expect(await db.select(db.syncQueue).get(), isEmpty);
  });

  test('pull idempotente: el segundo no aplica cambios', () async {
    servidor.seed('alquiler_decision', [
      _decision('ad-1'),
      _decision('ad-2', decision: 'DEVOLVER_AL_COLPORTOR'),
    ]);
    await motor.syncNow();

    final r = await motor.syncNow();

    expect(r.ok, isTrue);
    expect(r.pulled, 0);
    expect(await db.select(db.alquilerDecisiones).get(), hasLength(2));
  });

  test('una decisión deshecha (la persona volvió a la campaña) baja como baja lógica y deja de '
      'contar en «Mi alquiler»', () async {
    await db.customStatement(
      "INSERT INTO campania (id, nombre, fecha_inicio, created_at, updated_at) VALUES ('c-1', 'Otoño', '2026-03-01', 1, 1)",
    );
    await db.customStatement(
      "INSERT INTO campania_colportor (id, campania_id, usuario_id, created_at, updated_at, deleted_at) VALUES ('cc-1', 'c-1', 'col-1', 1, 1, 8)",
    );
    await db.customStatement(
      "INSERT INTO deposito (id, monto, fecha, destino, concepto, campania_id, validado_en, created_at, updated_at) VALUES ('d-1', 500000, 1, 'RETIRO_COORDINADOR', 'ALQUILER', 'c-1', 5, 1, 1)",
    );
    servidor.seed('alquiler_decision', [_decision('ad-1')]);
    await motor.syncNow();
    final fuente = AlquilerLocalDataSourceDrift(db);
    expect((await fuente.leer('col-1')).bajas.single.porDecidirCentavos, 0);

    servidor.seed('alquiler_decision', [
      _decision('ad-1', version: 2, baja: '2026-11-14T10:00:00+00:00'),
    ]);
    await motor.syncNow();

    expect(
      (await db.select(db.alquilerDecisiones).getSingle()).deletedAt,
      DateTime.utc(2026, 11, 14, 10),
    );
    final baja = (await fuente.leer('col-1')).bajas.single;
    expect(baja.decisiones, isEmpty);
    expect(baja.porDecidirCentavos, 500000);
  });

  test('error de red a mitad: no aplica nada y el próximo ciclo lo trae', () async {
    servidor.seed('alquiler_decision', [_decision('ad-1')]);
    servidor.failTransient();

    final cortado = await motor.syncNow();

    expect(cortado.failure, isNotNull);
    expect(await db.select(db.alquilerDecisiones).get(), isEmpty);

    final siguiente = await motor.syncNow();

    expect(siguiente.ok, isTrue);
    expect(await db.select(db.alquilerDecisiones).get(), hasLength(1));
  });

  test('un servidor que todavía no publica la entidad no rompe el pull de lo demás', () async {
    // Sin `seed('alquiler_decision', …)`: el servidor no tiene filas y el resto sigue.
    final r = await motor.syncNow();

    expect(r.ok, isTrue);
    expect(await db.select(db.alquilerDecisiones).get(), isEmpty);
  });
}
