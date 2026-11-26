// La transferencia de materiales de punta a punta (HU-STK-005, #512), con el código real de los dos lados
// de la frontera: el motor sube el alta que el colportor pidió y baja, por `DriftLocalStore`, lo que el
// servidor decide y las transferencias que le piden o arma la coordinadora («Ver transf.», a las dos
// puntas). `transferencia_stock` y `transferencia_item` son `push` con `alsoPull`.
import 'dart:convert';

import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/datos/encolador_sync_motor.dart';
import 'package:colportores_mobile/features/transferencias/data/datasources/transferencia_local_data_source_drift.dart';
import 'package:colportores_mobile/features/transferencias/data/repositories/transferencia_repository_impl.dart';
import 'package:colportores_mobile/features/transferencias/domain/entities/transferencia.dart';
import 'package:colportores_mobile/features/transferencias/domain/usecases/cancelar_transferencia_use_case.dart';
import 'package:colportores_mobile/features/transferencias/domain/usecases/pedir_transferencia_use_case.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../helpers/logger_mudo.dart';

/// El encabezado tal como lo entrega el servidor en el pull.
Map<String, Object?> _fila(
  String id, {
  String origen = 'ana',
  String destino = 'juan',
  String estado = 'PENDIENTE_AUTORIZACION',
  String? solicitante = 'juan',
  int version = 1,
  String? decididoEn,
  String? motivo,
  int numero = 18,
}) => {
  'id': id,
  'origen_id': origen,
  'destino_id': destino,
  'coordinador_id': decididoEn == null ? null : 'marta',
  'fecha_solicitud': '2026-10-23T17:35:04+00:00',
  'estado': estado,
  'solicitante_id': solicitante,
  'numero': numero,
  'monto_deuda': estado == 'AUTORIZADO' ? 120000 : null,
  'decidido_en': decididoEn,
  'motivo_rechazo': motivo,
  'baja_a_1': origen,
  'baja_a_2': destino,
  'created_at': '2026-10-23T17:35:00+00:00',
  'updated_at': '2026-10-23T17:35:04+00:00',
  'created_by': solicitante ?? 'marta',
  'deleted_at': null,
  'sync_version': version,
};

Map<String, Object?> _linea(String id, String transferencia, String producto, int cantidad) => {
  'id': id,
  'transferencia_id': transferencia,
  'producto_id': producto,
  'cantidad': cantidad,
  'precio_unitario': 60000,
  'solicitante_id': 'juan',
  'baja_a_1': 'ana',
  'baja_a_2': 'juan',
  'created_at': '2026-10-23T17:35:00+00:00',
  'updated_at': '2026-10-23T17:35:04+00:00',
  'created_by': 'juan',
  'deleted_at': null,
  'sync_version': 1,
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

  TransferenciaRepositoryImpl repositorio() => TransferenciaRepositoryImpl(
    TransferenciaLocalDataSourceDrift(db, encolador: EncoladorSyncMotor(motor)),
    logger: loggerMudo(),
  );

  Future<List<Transferencia>> transferencias([String usuario = 'juan']) =>
      repositorio().observar(usuario).first;

  test('el catálogo declara las dos entidades como push con pull', () {
    for (final entidad in ['transferencia_stock', 'transferencia_item']) {
      final spec = specsDeLaApp.singleWhere((s) => s.entity == entidad);
      expect(spec.policy, SyncPolicy.push, reason: entidad);
      expect(spec.alsoPull, isTrue, reason: entidad);
      expect(spec.pullable, isTrue, reason: entidad);
    }
  });

  test(
    'lo que baja: una transferencia que le piden al colportor llega con sus líneas y su estado',
    () async {
      servidor
        ..seed('transferencia_stock', [
          _fila('t-9', origen: 'juan', destino: 'bruno', solicitante: 'bruno'),
        ])
        ..seed('transferencia_item', [_linea('l-9', 't-9', 'p-9', 10)]);

      final r = await motor.syncNow();

      expect(r.ok, isTrue);
      final t = (await transferencias()).single;
      expect(t.id, 't-9');
      expect(t.origenId, 'juan');
      expect(t.estado, EstadoDeTransferencia.porAutorizar);
      expect(t.laPidio('juan'), isFalse);
      expect(t.solicitanteId, 'bruno');
      expect(t.numero, 18);
      expect(t.enCola, isFalse);
      expect(t.lineas.single.cantidad, 10);
    },
  );

  test('la que arma la coordinadora llega a las dos puntas, sin solicitante', () async {
    servidor
      ..seed('transferencia_stock', [_fila('t-c', solicitante: null)])
      ..seed('transferencia_item', [_linea('l-c', 't-c', 'p-1', 2)]);

    await motor.syncNow();

    final t = (await transferencias()).single;
    expect(t.solicitanteId, isNull);
    expect(t.esDeCoordinacion('juan'), isTrue);
    expect(t.laPuedeCancelar('juan'), isFalse);
  });

  test('un rechazo baja con su motivo y su hora', () async {
    servidor.seed('transferencia_stock', [
      _fila(
        't-1',
        estado: 'RECHAZADO',
        decididoEn: '2026-10-23T12:12:00+00:00',
        motivo: 'Ana los necesita esta semana',
      ),
    ]);

    await motor.syncNow();

    final t = (await transferencias()).single;
    expect(t.estado, EstadoDeTransferencia.rechazada);
    expect(t.motivoRechazo, 'Ana los necesita esta semana');
    expect(t.decididoEn, DateTime.utc(2026, 10, 23, 12, 12));
  });

  test('el pull no encola nada: lo que baja del servidor no vuelve a subir', () async {
    servidor
      ..seed('transferencia_stock', [
        _fila('t-1'),
        _fila('t-2', estado: 'AUTORIZADO', decididoEn: '2026-10-23T12:12:00+00:00'),
      ])
      ..seed('transferencia_item', [_linea('l-1', 't-1', 'p-1', 2)]);

    await motor.syncNow();

    expect(await db.select(db.syncQueue).get(), isEmpty);
  });

  test('pedida en el teléfono: sube el alta (encabezado antes que las líneas) y la misma fila baja '
      'aceptada, sin duplicarse ni volver a subir', () async {
    final caso = PedirTransferenciaUseCase(
      repositorio(),
      ahora: () => DateTime.utc(2026, 10, 23, 17, 35),
    );
    final r = await caso(
      const PedirTransferenciaParams(
        transferenciaId: 't-1',
        colportorId: 'juan',
        entregaId: 'ana',
        materiales: [MaterialPedido(productoId: 'p-1', cantidad: 2)],
        idsDeLineas: ['l-1'],
      ),
    );
    expect(r.isRight(), isTrue);
    expect((await transferencias()).single.enCola, isTrue);

    final cola = await db.select(db.syncQueue).get();
    expect([for (final j in cola) j.entity], ['transferencia_stock', 'transferencia_item']);
    for (final trabajo in cola) {
      final payload = jsonDecode(trabajo.payload) as Map<String, Object?>;
      expect(payload.keys, isNot(contains('solicitante_id')));
      expect(payload.keys, isNot(contains('numero')));
      expect(payload.keys, isNot(contains('fecha_solicitud')));
    }

    final subida = await motor.syncNow();
    expect(subida.ok, isTrue);
    servidor
      ..seed('transferencia_stock', [_fila('t-1', version: 2)])
      ..seed('transferencia_item', [_linea('l-1', 't-1', 'p-1', 2)]);
    final bajada = await motor.syncNow();

    expect(bajada.ok, isTrue);
    final todas = await transferencias();
    expect(todas, hasLength(1));
    expect(todas.single.enCola, isFalse);
    expect(todas.single.laPidio('juan'), isTrue);
    expect(todas.single.lineas, hasLength(1));
  });

  test('cancelada sin conexión y subida después: el alta y la cancelación no se pierden', () async {
    final caso = PedirTransferenciaUseCase(
      repositorio(),
      ahora: () => DateTime.utc(2026, 10, 23, 17, 35),
    );
    await caso(
      const PedirTransferenciaParams(
        transferenciaId: 't-1',
        colportorId: 'juan',
        entregaId: 'ana',
        materiales: [MaterialPedido(productoId: 'p-1', cantidad: 2)],
        idsDeLineas: ['l-1'],
      ),
    );
    final cancelar = CancelarTransferenciaUseCase(
      repositorio(),
      ahora: () => DateTime.utc(2026, 10, 23, 17, 40),
    );

    final r = await cancelar(
      const CancelarTransferenciaParams(transferenciaId: 't-1', colportorId: 'juan'),
    );

    expect(r.isRight(), isTrue);
    expect((await transferencias()).single.estado, EstadoDeTransferencia.cancelada);
    final subida = await motor.syncNow();
    expect(subida.ok, isTrue);
  });

  test('error de red a mitad: no aplica nada y el próximo ciclo lo trae', () async {
    servidor.seed('transferencia_stock', [
      _fila('t-1', estado: 'AUTORIZADO', decididoEn: '2026-10-23T12:12:00+00:00'),
    ]);
    servidor.failTransient();

    final cortado = await motor.syncNow();

    expect(cortado.failure, isNotNull);
    expect(await transferencias(), isEmpty);
    final r = await motor.syncNow();
    expect(r.ok, isTrue);
    expect((await transferencias()).single.estado, EstadoDeTransferencia.autorizada);
  });
}
