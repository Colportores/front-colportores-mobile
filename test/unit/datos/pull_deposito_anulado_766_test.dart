// «El depósito de alquiler que el coordinador devolvió baja anulado al teléfono» (#766, hueco que
// vio la revisión de compatibilidad del 24/11; backend-supabase 0167): el motor real baja el delta
// de un servidor falso y `deposito.anulado_at` entra por `DriftLocalStore` a la tabla local, con el
// código real de los dos lados de la frontera. Un pago anulado no suma a «Depositado».
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/datos/encolador_sync_motor.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/deposito_local_data_source_drift.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/totales_de_depositos_drift.dart';
import 'package:colportores_mobile/features/depositos/data/repositories/deposito_repository_impl.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../helpers/logger_mudo.dart';

const _validado = '2026-10-29T09:30:00+00:00';
const _anulado = '2026-11-05T14:00:00+00:00';

/// La fila de `deposito` de un pago de alquiler tal como la entrega el servidor en el pull.
Map<String, Object?> _fila(
  String id, {
  int monto = 250000,
  int version = 1,
  String? validadoEn = _validado,
  String? anuladoAt,
}) => {
  'id': id,
  'colportor_id': 'col-1',
  'monto': monto,
  'fecha': '2026-10-28T15:00:00+00:00',
  'destino': 'RETIRO_COORDINADOR',
  'concepto': 'ALQUILER',
  'campania_id': 'c-1',
  'ticket_id': null,
  'validado_en': validadoEn,
  'validado_por': validadoEn == null ? null : 'coord-1',
  'rechazado_en': null,
  'rechazado_por': null,
  'motivo_rechazo': null,
  'anulado_at': anuladoAt,
  'created_at': '2026-10-28T15:00:00+00:00',
  'updated_at': '2026-10-28T15:00:00+00:00',
  'created_by': 'col-1',
  'deleted_at': null,
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

  Future<List<Deposito>> depositos() async => (await DepositoRepositoryImpl(
    DepositoLocalDataSourceDrift(db, encolador: EncoladorSyncMotor(motor)),
    logger: loggerMudo(),
  ).todos()).getOrElse(() => []);

  test('un depósito de alquiler devuelto baja con su `anulado_at`', () async {
    servidor.seed('deposito', [_fila('d-1', anuladoAt: _anulado)]);

    final r = await motor.syncNow();

    expect(r.ok, isTrue);
    expect(r.pulled, 1);
    final d = (await depositos()).single;
    expect(d.anuladoAt, DateTime.utc(2026, 11, 5, 14));
    expect(d.validadoEn, DateTime.utc(2026, 10, 29, 9, 30));
  });

  test('uno que no se devolvió baja con `anulado_at` vacío', () async {
    servidor.seed('deposito', [_fila('d-1')]);

    await motor.syncNow();

    expect((await depositos()).single.anuladoAt, isNull);
  });

  test(
    'el pago ya validado que después se devuelve: el mismo depósito se anula y deja de sumar',
    () async {
      servidor.seed('deposito', [_fila('d-1')]);
      await motor.syncNow();
      final totales = TotalesDeDepositosDrift(db);
      expect(await totales.validado(), 250000);

      servidor.seed('deposito', [_fila('d-1', version: 2, anuladoAt: _anulado)]);
      final r = await motor.syncNow();

      expect(r.ok, isTrue);
      final todos = await depositos();
      expect(todos, hasLength(1), reason: 'es la misma fila, no una segunda');
      expect(todos.single.anuladoAt, DateTime.utc(2026, 11, 5, 14));
      expect(await totales.validado(), 0, reason: 'un pago devuelto no suma a «Depositado»');
    },
  );

  test('lo anulado que baja no vuelve a subir y repetir el pull no cambia nada', () async {
    servidor.seed('deposito', [_fila('d-1', anuladoAt: _anulado)]);
    await motor.syncNow();

    final otra = await motor.syncNow();

    expect(otra.ok, isTrue);
    expect(otra.pulled, 0);
    expect(await db.select(db.syncQueue).get(), isEmpty);
    expect((await depositos()).single.anuladoAt, DateTime.utc(2026, 11, 5, 14));
  });
}
