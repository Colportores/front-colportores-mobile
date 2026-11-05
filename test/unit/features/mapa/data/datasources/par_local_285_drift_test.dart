// HU-UBI-006, «Par local» (#285): la unión de un par en el que una de las dos ubicaciones solo está en
// el teléfono. Contra el motor de sync REAL (la cola `sync_queue` sobre la DB en memoria) y un servidor
// que hace lo de la 0017: una `ubicacion` viva con una calle ocupada vuelve `conflict` 23505, y lo que
// la nombra en el mismo lote queda `ESPERA_ALTA_EN_CONFLICTO`.
//
// Contrato del motor, §2.3 y §6.2: no se encola «marcar como duplicado»; lo que colgaba de la
// rechazada se reapunta a la conservada y sube con los trabajos de siempre; la rechazada queda de baja
// en el teléfono, sin borrarse y sin subir.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/datos/encolador_sync_motor.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/ubicacion_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/data/services/consultor_alta_ubicacion_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/duplicados_ubicacion_use_cases.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/duplicados_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

/// El servidor de la 0017: ver `packages/sync_engine/test/en_espera_test.dart`.
class _Servidor implements SyncTransport {
  _Servidor({this.ocupadas = const {}});

  final Set<String> ocupadas;
  final Map<String, Map<String, Object?>> filas = {};

  @override
  Future<PushResult> push(PushBatch batch) async {
    final enEspera = <String>{};
    final resultados = <JobResult>[];
    for (final job in batch.jobs) {
      final pk = (job.payload['id'] ?? job.payload['ubicacion_id'])! as String;
      final nombra = {pk, ...job.payload.values.whereType<String>()};
      final espera = nombra.intersection(enEspera);
      if (espera.isNotEmpty) {
        enEspera.add(pk);
        resultados.add(
          JobResult(
            clientOpId: job.clientOpId,
            outcome: JobOutcome.conflict,
            code: kCodigoEsperaAltaEnConflicto,
            dependsOn: espera.first,
          ),
        );
        continue;
      }
      final faltante = job.payload.entries.any(
        (e) =>
            e.key.endsWith('_id') &&
            e.key != 'created_by' &&
            e.key != 'ciudad_id' &&
            e.value is String &&
            !filas.containsKey(e.value),
      );
      if (faltante) {
        resultados.add(
          JobResult(clientOpId: job.clientOpId, outcome: JobOutcome.invalid, code: '23503'),
        );
        continue;
      }
      final fila = {...?filas[pk], ...job.payload};
      if (job.entity == 'ubicacion' &&
          fila['deleted_at'] == null &&
          ocupadas.contains(fila['calle']) &&
          !filas.containsKey(pk)) {
        enEspera.add(pk);
        resultados.add(
          JobResult(
            clientOpId: job.clientOpId,
            outcome: JobOutcome.conflict,
            code: '23505',
            constraint: 'ubicacion_direccion_unica',
          ),
        );
        continue;
      }
      filas[pk] = fila;
      resultados.add(JobResult(clientOpId: job.clientOpId, outcome: JobOutcome.accepted));
    }
    return PushResult(serverTime: DateTime.utc(2026, 11, 4), results: resultados);
  }

  @override
  Future<PullDelta> pull({required List<String> entities, String? watermark, int? limit}) async =>
      PullDelta(
        serverTime: DateTime.utc(2026, 11, 4),
        watermark: watermark ?? '0',
        hasMore: false,
        rows: const {},
      );
}

UbicacionModel _ubicacion(String id) => UbicacionModel.fromJson({
  'id': id,
  'tipo': 'CASA',
  'calle': 'Rivera',
  'numero': '1234',
  'lat': -34.9,
  'lon': -56.16,
  'ciudad_id': 'ciu-1',
  'zona_id': null,
  'created_at': '2026-11-04T12:00:00.000Z',
  'updated_at': '2026-11-04T12:00:00.000Z',
  'created_by': 'col-1',
  'deleted_at': null,
  'sync_version': 0,
});

EspacioModel _espacio(String id, String ubicacionId, {String? depto}) => EspacioModel.fromJson({
  'id': id,
  'ubicacion_id': ubicacionId,
  'numero_depto': depto,
  'piso': null,
  'created_at': '2026-11-04T12:00:00.000Z',
  'updated_at': '2026-11-04T12:00:00.000Z',
  'created_by': 'col-1',
  'deleted_at': null,
  'sync_version': 0,
});

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final ahora = DateTime.utc(2026, 11, 4, 15);

  late AppDatabase db;
  late _Servidor servidor;
  late SyncEngine motor;
  late UbicacionLocalDataSourceDrift local;
  late EncoladorMarcarDuplicadoFalso marcador;
  late UnirDuplicadosUseCase unir;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    servidor = _Servidor(ocupadas: {'Rivera'});
    motor = SyncEngine(
      specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
      transport: servidor,
      jobs: DriftJobStore(db),
      store: DriftLocalStore(db, entidades: entidadesQueEscribeElMotor),
    );
    marcador = EncoladorMarcarDuplicadoFalso();
    local = UbicacionLocalDataSourceDrift(
      db,
      encolador: EncoladorSyncMotor(motor),
      marcarDuplicado: marcador,
    );
    unir = UnirDuplicadosUseCase(
      UbicacionRepositoryImpl(local, logger: loggerMudo()),
      ahora: () => ahora,
    );
  });

  tearDown(() async {
    await motor.dispose();
    await db.close();
  });

  /// A, que ya está en el servidor (la bajó el pull: sin job), con su espacio único.
  Future<void> sembrarAEnElServidor() async {
    await sembrarUbicacion(db, id: 'ub-a');
    await sembrarEspacio(db, id: 'esp-a', ubicacionId: 'ub-a');
    servidor.filas['ub-a'] = {'id': 'ub-a', 'calle': 'Rivera'};
    servidor.filas['esp-a'] = {'id': 'esp-a', 'ubicacion_id': 'ub-a'};
    servidor.filas['per-b1'] = {'id': 'per-b1'};
  }

  /// B, la de Ana: su alta con el espacio único, y un vínculo que cuelga del espacio.
  Future<void> cargarB() async {
    await local.insertar(_ubicacion('ub-b'), espacio: _espacio('esp-b', 'ub-b'));
    await sembrarVinculo(db, id: 'ep-b1', espacioId: 'esp-b', personaId: 'per-b1');
    await motor.stage('espacio_persona', Op.insert, {
      'id': 'ep-b1',
      'espacio_id': 'esp-b',
      'persona_id': 'per-b1',
    });
  }

  Future<UbicacionFila> fila(String id) =>
      (db.select(db.ubicaciones)..where((u) => u.id.equals(id))).getSingle();

  Future<List<QueuedJob>> retenidos() => DriftJobStore(db).listHeld();

  Future<Map<String, EstadoAltaUbicacion>> sinConfirmar() =>
      ConsultorAltaUbicacionDrift(db).observarSinConfirmar().first;

  group('Par local: el alta de B volvió en conflicto (dirección única, D1)', () {
    test('se une en el teléfono: no encola nada, B queda de baja sin borrarse, lo que colgaba sube '
        'reapuntado a A y nada queda en espera', () async {
      await sembrarAEnElServidor();
      await cargarB();
      await motor.syncNow();
      expect(await retenidos(), isNotEmpty, reason: 'el alta de B y lo que cuelga esperan');
      expect(await sinConfirmar(), {'ub-b': EstadoAltaUbicacion.soloEnTelefono});

      final r = await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'));

      expect(r.isRight(), isTrue);
      expect(marcador.encolados, isEmpty, reason: 'la RPC no conoce a B: no se encola la unión');
      final b = await fila('ub-b');
      expect(b.deletedAt, ahora, reason: 'B queda de baja en el teléfono, sin borrarse');
      expect(
        await retenidos(),
        isEmpty,
        reason: 'sale de «en espera» y el alta ya no se reintenta',
      );
      expect(await sinConfirmar(), isEmpty);

      final resultado = await motor.syncNow();
      expect(resultado.ok, isTrue);
      expect(servidor.filas.containsKey('ub-b'), isFalse, reason: 'B nunca sube');
      expect(
        servidor.filas.containsKey('esp-b'),
        isFalse,
        reason: 'el único de B se fundió en el de A',
      );
      expect(servidor.filas['ep-b1']!['espacio_id'], 'esp-a');
      expect((await DriftJobStore(db).status()).pending, 0);
      expect((await DriftJobStore(db).status()).invalid, 0);
    });

    test('los deptos de B pasan a A y suben con la ubicación de A', () async {
      await sembrarAEnElServidor();
      await cargarB();
      // Un depto más en B (la casa pasa a edificio al unirse): sembrado y encolado como lo haría la
      // edición, sin la regla de «una casa no tiene deptos» de la hoja.
      await sembrarEspacio(db, id: 'esp-b3', ubicacionId: 'ub-b', numeroDepto: '3');
      await motor.stage('espacio', Op.insert, {
        'id': 'esp-b3',
        'ubicacion_id': 'ub-b',
        'numero_depto': '3',
      });
      await motor.syncNow();

      final r = await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'));

      expect(r.isRight(), isTrue);
      expect(marcador.encolados, isEmpty);
      expect(await retenidos(), isEmpty);
      expect((await motor.syncNow()).ok, isTrue);
      expect(servidor.filas['esp-b3']!['ubicacion_id'], 'ub-a');
      expect(servidor.filas['ub-a']!['tipo'], 'EDIFICIO', reason: 'A quedó con dos espacios');
      expect(servidor.filas['ep-b1']!['espacio_id'], 'esp-a');
      expect(servidor.filas.containsKey('ub-b'), isFalse);
    });

    test('no se puede conservar la que solo está en el teléfono: no cambia nada', () async {
      await sembrarAEnElServidor();
      await cargarB();
      await motor.syncNow();

      final r = await unir(const UnirDuplicadosParams(conservarId: 'ub-b', duplicadaId: 'ub-a'));

      expect(r.fold((f) => f, (_) => null), isA<FailureConservadaSoloEnTelefono>());
      expect((await fila('ub-a')).deletedAt, isNull);
      expect((await fila('ub-b')).deletedAt, isNull);
      expect(marcador.encolados, isEmpty);
      expect(await retenidos(), isNotEmpty, reason: 'lo de B sigue en espera, sin perderse');
    });
  });

  group('Par local: el alta de B todavía está PENDING', () {
    test(
      'se une en el teléfono sin encolar la unión: B no sube viva y lo suyo sube en A',
      () async {
        await sembrarAEnElServidor();
        await cargarB();
        expect(await sinConfirmar(), {'ub-b': EstadoAltaUbicacion.soloEnTelefono});

        final r = await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'));

        expect(r.isRight(), isTrue);
        expect(marcador.encolados, isEmpty);
        expect((await fila('ub-b')).deletedAt, ahora);

        expect((await motor.syncNow()).ok, isTrue);
        final deB = servidor.filas['ub-b'];
        expect(
          deB == null || deB['deleted_at'] != null,
          isTrue,
          reason: 'B no queda viva en el servidor',
        );
        expect(servidor.filas['ep-b1']!['espacio_id'], 'esp-a');
        expect(await retenidos(), isEmpty);
        expect((await DriftJobStore(db).status()).pending, 0);
        expect((await DriftJobStore(db).status()).invalid, 0);
      },
    );
  });

  group('Par local: el alta de B está subiendo (IN_FLIGHT)', () {
    test('la unión espera la respuesta: no cambia nada y se puede reintentar', () async {
      await sembrarAEnElServidor();
      await cargarB();
      await DriftJobStore(db).claimPending();
      expect(await sinConfirmar(), {'ub-b': EstadoAltaUbicacion.subiendo});

      final r = await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'));

      expect(r.fold((f) => f, (_) => null), isA<FailureAltaSubiendo>());
      expect((await fila('ub-b')).deletedAt, isNull);
      expect(marcador.encolados, isEmpty);
      final espacio = await (db.select(
        db.espacios,
      )..where((e) => e.id.equals('esp-b'))).getSingle();
      expect(espacio.deletedAt, isNull, reason: 'no se tocó nada de B');
    });

    test('si el servidor la acepta, la unión se encola como cualquier otra', () async {
      await sembrarAEnElServidor();
      servidor.ocupadas.clear();
      await cargarB();
      await motor.syncNow();
      expect(await sinConfirmar(), isEmpty, reason: 'las dos están en el servidor');

      final r = await unir(const UnirDuplicadosParams(conservarId: 'ub-a', duplicadaId: 'ub-b'));

      expect(r.isRight(), isTrue);
      expect(marcador.encolados, [(duplicadaId: 'ub-b', conservadaId: 'ub-a')]);
    });
  });
}
