// «El teléfono ve la validación y el rechazo» de punta a punta (#596), con el código real de los dos
// lados de la frontera: el motor baja el delta de un servidor falso y lo que baja entra por
// `DriftLocalStore` a la tabla `deposito`. `deposito` es `push` con `alsoPull`: sube lo que el
// colportor registra y baja el mismo depósito con `validado_*` o `rechazado_*` que pone el servidor.
import 'dart:convert';

import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/datos/encolador_sync_motor.dart';
import 'package:colportores_mobile/features/depositos/data/datasources/deposito_local_data_source_drift.dart';
import 'package:colportores_mobile/features/depositos/data/repositories/deposito_repository_impl.dart';
import 'package:colportores_mobile/features/depositos/domain/entities/deposito.dart';
import 'package:colportores_mobile/features/depositos/domain/usecases/registrar_deposito_use_case.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../helpers/logger_mudo.dart';

/// La fila de `deposito` tal como la entrega el servidor en el pull.
Map<String, Object?> _fila(
  String id, {
  int monto = 180000,
  String destino = 'BANCO',
  String? ticketId = 't-1',
  int version = 1,
  String? validadoEn,
  String? validadoPor,
  String? rechazadoEn,
  String? motivoRechazo,
}) => {
  'id': id,
  'colportor_id': 'col-1',
  'monto': monto,
  'fecha': '2026-10-28T15:00:00+00:00',
  'destino': destino,
  'concepto': 'CASA_EDITORA',
  'campania_id': null,
  'ticket_id': ticketId,
  'validado_en': validadoEn,
  'validado_por': validadoPor,
  'rechazado_en': rechazadoEn,
  'rechazado_por': rechazadoEn == null ? null : 'coord-1',
  'motivo_rechazo': motivoRechazo,
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

  DepositoRepositoryImpl repositorio() => DepositoRepositoryImpl(
    DepositoLocalDataSourceDrift(db, encolador: EncoladorSyncMotor(motor)),
    logger: loggerMudo(),
  );

  Future<List<Deposito>> depositos() async => (await repositorio().todos()).getOrElse(() => []);

  test('el catálogo declara `deposito` como push, crítico y con pull', () {
    final spec = specsDeLaApp.singleWhere((s) => s.entity == 'deposito');

    expect(spec.policy, SyncPolicy.push);
    expect(spec.alsoPull, isTrue);
    expect(spec.critical, isTrue);
    expect(spec.pullable, isTrue);
  });

  test('un depósito validado baja con la fecha y quién lo validó, y se ve validado', () async {
    servidor.seed('deposito', [
      _fila('d-1', validadoEn: '2026-10-29T09:30:00+00:00', validadoPor: 'coord-1'),
    ]);

    final r = await motor.syncNow();

    expect(r.ok, isTrue);
    expect(r.pulled, 1);
    final d = (await depositos()).single;
    expect(d.estado, EstadoDeDeposito.validado);
    expect(d.validadoEn, DateTime.utc(2026, 10, 29, 9, 30));
    expect(d.validadoPor, 'coord-1');
    expect(d.rechazadoEn, isNull);
  });

  test('un retiro rechazado baja con su motivo, y se ve rechazado', () async {
    servidor.seed('deposito', [
      _fila(
        'd-2',
        monto: 600000,
        destino: 'RETIRO_COORDINADOR',
        ticketId: null,
        rechazadoEn: '2026-10-29T10:00:00+00:00',
        motivoRechazo: 'Recibí \$ 5.000, no \$ 6.000.',
      ),
    ]);

    await motor.syncNow();

    final d = (await depositos()).single;
    expect(d.estado, EstadoDeDeposito.rechazado);
    expect(d.rechazadoEn, DateTime.utc(2026, 10, 29, 10));
    expect(d.motivoRechazo, 'Recibí \$ 5.000, no \$ 6.000.');
    expect(d.validadoEn, isNull);
  });

  test('un depósito que todavía no respondió nadie baja por validar', () async {
    servidor.seed('deposito', [_fila('d-3')]);

    await motor.syncNow();

    expect((await depositos()).single.estado, EstadoDeDeposito.porValidar);
  });

  test('quien mira los depósitos se entera cuando el pull trae la validación', () async {
    servidor.seed('deposito', [_fila('d-1')]);
    await motor.syncNow();
    final vistos = <List<Deposito>>[];
    final suscripcion = repositorio().observar().listen(vistos.add);
    addTearDown(suscripcion.cancel);
    await pumpEventQueue();
    expect(vistos.last.single.estado, EstadoDeDeposito.porValidar);

    servidor.seed('deposito', [
      _fila('d-1', version: 2, validadoEn: '2026-10-29T09:30:00+00:00', validadoPor: 'coord-1'),
    ]);
    await motor.syncNow();
    await pumpEventQueue();

    expect(vistos.last.single.estado, EstadoDeDeposito.validado);
  });

  test('el pull no encola nada: lo que baja del servidor no vuelve a subir', () async {
    servidor.seed('deposito', [
      _fila('d-1', validadoEn: '2026-10-29T09:30:00+00:00', validadoPor: 'coord-1'),
      _fila('d-2', ticketId: 't-2'),
    ]);

    await motor.syncNow();

    expect(await db.select(db.syncQueue).get(), isEmpty);
  });

  test('pull idempotente: el segundo no aplica cambios y deja todo igual', () async {
    servidor.seed('deposito', [
      _fila('d-1', validadoEn: '2026-10-29T09:30:00+00:00', validadoPor: 'coord-1'),
    ]);
    await motor.syncNow();

    final r = await motor.syncNow();

    expect(r.ok, isTrue);
    expect(r.pulled, 0);
    expect(await depositos(), hasLength(1));
  });

  test('un depósito registrado en el teléfono sube por validar y, cuando el servidor lo valida, '
      'el mismo depósito baja validado: no se duplica ni se vuelve a subir', () async {
    // Registrado en el teléfono: nace por validar y queda en la cola.
    final caso = RegistrarDepositoUseCase(
      repositorio(),
      ahora: () => DateTime.utc(2026, 10, 28, 15),
    );
    final registrado = await caso(
      const RegistrarDepositoParams(
        depositoId: 'd-1',
        colportorId: 'col-1',
        montoCentavos: 180000,
        destino: DestinoDeDeposito.retiroCoordinador,
        concepto: ConceptoDeDeposito.casaEditora,
      ),
    );
    expect(registrado.isRight(), isTrue);
    expect((await depositos()).single.estado, EstadoDeDeposito.porValidar);

    // Sube, y después el coordinador lo valida en el servidor (versión nueva de la misma fila).
    final subida = await motor.syncNow();
    expect(subida.ok, isTrue);
    servidor.seed('deposito', [
      _fila(
        'd-1',
        destino: 'RETIRO_COORDINADOR',
        ticketId: null,
        version: 2,
        validadoEn: '2026-10-29T09:30:00+00:00',
        validadoPor: 'coord-1',
      ),
    ]);
    final bajada = await motor.syncNow();

    expect(bajada.ok, isTrue);
    final todos = await depositos();
    expect(todos, hasLength(1));
    expect(todos.single.id, 'd-1');
    expect(todos.single.estado, EstadoDeDeposito.validado);
    // Lo único que subió fue el alta, y sin las columnas del servidor.
    final cola = await db.select(db.syncQueue).get();
    for (final trabajo in cola) {
      final payload = jsonDecode(trabajo.payload) as Map<String, Object?>;
      expect(payload.keys, isNot(contains('validado_en')));
      expect(payload.keys, isNot(contains('rechazado_en')));
      expect(payload.keys, isNot(contains('motivo_rechazo')));
    }
  });

  test('error de red a mitad: no aplica nada y el próximo ciclo lo trae', () async {
    servidor.seed('deposito', [_fila('d-1', validadoEn: '2026-10-29T09:30:00+00:00')]);
    servidor.failTransient();

    final cortado = await motor.syncNow();

    expect(cortado.failure, isNotNull);
    expect(await depositos(), isEmpty);
    final r = await motor.syncNow();
    expect(r.ok, isTrue);
    expect((await depositos()).single.estado, EstadoDeDeposito.validado);
  });
}
