// El depósito con el cableado real (HU-CTA-004, #442): la cola del motor, el push al servidor y los
// providers. Lo que no cubre el fake del encolador: que `deposito` esté declarado en el catálogo y
// que su payload sea el que el motor sube.
import 'dart:convert';

import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/sync/sync_providers.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/datos/encolador_sync_motor.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/deposito_local_data_source_drift.dart';
import 'package:colportores_mobile/features/depositos/data/repositories/deposito_repository_impl.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/depositos/domain/usecases/registrar_deposito_use_case.dart';
import 'package:colportores_mobile/features/depositos/presentation/providers/depositos_providers.dart';
import 'package:drift/drift.dart' show OrderingTerm, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../../../helpers/logger_mudo.dart';

final _ahora = DateTime.utc(2026, 10, 30, 12, 0, 7, 321);

final _uuidV7 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase? _db;

  @override
  AppDatabase? build() => _db;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late FakeSyncTransport servidor;
  late FakeConnectivityPort red;
  late SyncEngine motor;
  late RegistrarDepositoUseCase caso;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    servidor = FakeSyncTransport(pkFieldPorEntidad: const {'house_status': 'ubicacion_id'});
    red = FakeConnectivityPort();
    motor = SyncEngine(
      specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
      transport: servidor,
      jobs: DriftJobStore(db),
      store: DriftLocalStore(db, entidades: entidadesQueEscribeElMotor),
      connectivity: red,
    );
    caso = RegistrarDepositoUseCase(
      DepositoRepositoryImpl(
        DepositoLocalDataSourceDrift(db, encolador: EncoladorSyncMotor(motor)),
        logger: loggerMudo(),
      ),
      ahora: () => _ahora,
    );
  });
  tearDown(() async {
    await motor.dispose();
    await red.dispose();
    await db.close();
  });

  RegistrarDepositoParams params(String id, {String? ticketId = 't-1'}) => RegistrarDepositoParams(
    depositoId: id,
    colportorId: 'col-1',
    montoCentavos: 180000,
    destino: ticketId == null ? DestinoDeDeposito.retiroCoordinador : DestinoDeDeposito.banco,
    concepto: ConceptoDeDeposito.casaEditora,
    ticketId: ticketId,
  );

  Future<List<SyncQueueFila>> cola() =>
      (db.select(db.syncQueue)..orderBy([(j) => OrderingTerm.asc(j.createdAt)])).get();

  test('dado el catálogo de la app, cuando se pregunta por `deposito`, sube por push, es solo de '
      'alta y no baja', () {
    final spec = specsDeLaApp.singleWhere((s) => s.entity == 'deposito');

    expect(spec.policy, SyncPolicy.push);
    expect(spec.alsoPull, isFalse);
    // Escritura crítica, como el cobro: mueve plata y sube sin esperar al próximo ciclo.
    expect(spec.critical, isTrue);
    expect(spec.pk, 'id');
    expect(entidadesDelBackup, contains('deposito'));
  });

  test('dado un depósito, cuando se registra, la cola real tiene el alta con las columnas del '
      'servidor', () async {
    final r = await caso(params('d-1'));

    expect(r.isRight(), isTrue);
    final trabajo = (await cola()).single;
    expect(trabajo.entity, 'deposito');
    expect(trabajo.op, 'insert');
    final payload = jsonDecode(trabajo.payload) as Map<String, Object?>;
    expect(payload['id'], 'd-1');
    expect(payload['monto'], 180000);
    expect(payload['destino'], 'BANCO');
    expect(payload['concepto'], 'CASA_EDITORA');
    expect(payload['ticket_id'], 't-1');
    expect(payload['fecha'], '2026-10-30T12:00:07.321Z');
    expect(payload.keys, isNot(contains('colportor_id')));
  });

  test('dado el depósito encolado, cuando sincroniza, el servidor recibe la fila y la cola queda '
      'sin trabajos pendientes', () async {
    await caso(params('d-1'));

    final r = await motor.syncNow();

    expect(r.ok, isTrue, reason: '$r');
    final filas = servidor.rowsOf('deposito');
    expect(filas, hasLength(1));
    expect(filas.single['monto'], 180000);
    expect(filas.single['ticket_id'], 't-1');
    expect([for (final j in await cola()) j.state], everyElement('DONE'));
  });

  test('dado un doble toque antes de sincronizar, cuando sincroniza, el servidor recibe un solo '
      'depósito', () async {
    await Future.wait([caso(params('d-1')), caso(params('d-1'))]);

    final r = await motor.syncNow();

    expect(r.ok, isTrue, reason: '$r');
    expect(servidor.rowsOf('deposito'), hasLength(1));
    expect(await cola(), hasLength(1));
  });

  test('dado dos depósitos seguidos, cuando sincroniza, suben los dos en el orden en que se '
      'registraron', () async {
    await caso(params('d-1', ticketId: 't-1'));
    await caso(params('d-2', ticketId: null));

    final r = await motor.syncNow();

    expect(r.ok, isTrue, reason: '$r');
    expect(servidor.rowsOf('deposito').map((f) => f['id']), ['d-1', 'd-2']);
  });

  test(
    'dado el provider real, cuando registra, usa un UUID v7 para generar ids y la hora de ahora',
    () async {
      final contenedor = ProviderContainer(
        overrides: [
          dbLocalProvider.overrideWith(() => _DbFija(db)),
          transporteSyncProvider.overrideWithValue(servidor),
          relojDepositoProvider.overrideWithValue(() => _ahora),
        ],
      );
      addTearDown(contenedor.dispose);
      final id = contenedor.read(generadorIdDepositoProvider)();

      final r = await contenedor.read(registrarDepositoUseCaseProvider)(params(id));

      final d = r.getOrElse(() => throw StateError('falló')).deposito;
      expect(d.id, matches(_uuidV7));
      expect(d.fecha, _ahora);
      expect((await contenedor.read(depositoRepositoryProvider).todos()).isRight(), isTrue);
    },
  );

  test(
    'dado el provider sin la DB abierta, cuando se lee, lanza (la pantalla lo traduce a un error)',
    () {
      final contenedor = ProviderContainer(
        overrides: [dbLocalProvider.overrideWith(() => _DbFija(null))],
      );
      addTearDown(contenedor.dispose);

      expect(() => contenedor.read(depositoRepositoryProvider), throwsA(anything));
    },
  );
}
