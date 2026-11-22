// La unión rechazada con lo que Ana hizo entre la unión y el rechazo (HU-UBI-006, #696; decisión de
// Cristian, 11/11, «Edic. unión» y «Visita unión»), de punta a punta con el código real de los dos
// lados: los DAOs escriben en la DB Drift y encolan por el motor, que sube a un servidor falso que
// compara `sync_version` (§5.4). Lo que se editó después de unir subió del lado de A; al deshacer la
// unión, el teléfono lo reenvía ya en B y el servidor termina igual que el teléfono.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/datos/encolador_marcar_duplicado_motor.dart';
import 'package:colportores_mobile/datos/encolador_sync_motor.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../helpers/campo_falsos.dart' hide t0;
import '../../helpers/logger_mudo.dart';

const _a = 'ub-0000000000000000000000000001';
const _b = 'ub-0000000000000000000000000002';

UbicacionModel _ubicacion(String id, {String tipo = 'CASA', String numero = '1234'}) =>
    UbicacionModel.fromJson({
      'id': id,
      'tipo': tipo,
      'calle': 'Rivera',
      'numero': numero,
      'lat': -34.9,
      'lon': -56.16,
      'ciudad_id': 'ciu-1',
      'zona_id': null,
      'created_at': '2026-10-16T12:00:00.000Z',
      'updated_at': '2026-10-16T12:00:00.000Z',
      'created_by': 'col-1',
      'deleted_at': null,
      'sync_version': 0,
    });

EspacioModel _espacio(String id, String ubicacionId, {String? depto}) => EspacioModel.fromJson({
  'id': id,
  'ubicacion_id': ubicacionId,
  'numero_depto': depto,
  'piso': null,
  'created_at': '2026-10-16T12:00:00.000Z',
  'updated_at': '2026-10-16T12:00:00.000Z',
  'created_by': 'col-1',
  'deleted_at': null,
  'sync_version': 0,
});

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final tUnion = DateTime.utc(2026, 10, 16, 13);
  final tDespues = DateTime.utc(2026, 10, 16, 13, 5);
  final tDeshacer = DateTime.utc(2026, 10, 16, 13, 10);

  late AppDatabase db;
  late FakeSyncTransport servidor;
  late SyncEngine motor;
  late UbicacionLocalDataSourceDrift ubicaciones;
  late AgendaLocalDataSourceDrift agendas;
  late DateTime reloj;

  setUp(() {
    reloj = DateTime.utc(2026, 10, 16, 12);
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    servidor = FakeSyncTransport(pkFieldPorEntidad: const {'house_status': 'ubicacion_id'});
    motor = SyncEngine(
      specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
      transport: servidor,
      jobs: DriftJobStore(db),
      store: DriftLocalStore(db, entidades: entidadesQueEscribeElMotor),
      clock: () => reloj,
    );
    final encolador = EncoladorSyncMotor(motor);
    ubicaciones = UbicacionLocalDataSourceDrift(
      db,
      encolador: encolador,
      marcarDuplicado: EncoladorMarcarDuplicadoMotor(motor),
    );
    agendas = AgendaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
    );
  });
  tearDown(() async {
    await motor.dispose();
    await db.close();
  });

  Future<SyncQueueFila> trabajoDeUnion() =>
      (db.select(db.syncQueue)..where((q) => q.op.equals('marcar_como_duplicado'))).getSingle();

  Map<String, Object?> enElServidor(String entidad, String id) =>
      servidor.rowsOf(entidad).firstWhere((f) => f['id'] == id);

  Future<List<SyncQueueFila>> trabajosDe(String entidad, String id) =>
      (db.select(db.syncQueue)..where((q) => q.entity.equals(entidad) & q.rowPk.equals(id))).get();

  /// Une B con A a [tUnion], deja que [despues] escriba a [tDespues], rechaza la unión y sube: el
  /// servidor aplica lo de después (del lado de A) y rechaza la unión.
  Future<void> unirEditarYRechazar(Future<void> Function() despues) async {
    reloj = tUnion;
    final union = await ubicaciones.unirDuplicada(_a, _b, ahora: tUnion);
    expect(union.escribio, isTrue);
    reloj = tDespues;
    await despues();
    servidor.rejectJob((await trabajoDeUnion()).clientOpId, 'UB003');
    final resultado = await motor.syncNow();
    expect(resultado.invalidated, 1);
    expect((await trabajoDeUnion()).state, 'INVALID');
  }

  Future<void> deshacerYSubir() async {
    reloj = tDeshacer;
    final [deshecha] = await ubicaciones.deshacerUnionesRechazadas(ahora: tDeshacer);
    expect(deshecha.sinVolver, 0);
    final otraVuelta = await motor.syncNow();
    expect(otraVuelta.ok, isTrue);
    expect(otraVuelta.invalidated, 0);
  }

  test('«Edic. unión»: dado un depto de B editado después de unir, cuando el servidor rechaza la '
      'unión, el teléfono reenvía el depto y el servidor y el teléfono lo tienen en B con la '
      'edición', () async {
    await ubicaciones.insertar(_ubicacion(_a), espacio: _espacio('esp-a', _a));
    await ubicaciones.insertar(
      _ubicacion(_b, tipo: 'EDIFICIO', numero: '1236'),
      espacio: _espacio('esp-b2', _b, depto: '2B'),
    );
    await ubicaciones.insertarEspacio(_espacio('esp-b3', _b, depto: '3B'));
    await motor.syncNow();

    await unirEditarYRechazar(
      () => ubicaciones.actualizarEspacio('esp-b2', numeroDepto: '2C', ahora: tDespues),
    );
    expect(
      enElServidor('espacio', 'esp-b2')['ubicacion_id'],
      _a,
      reason: 'el problema: subió en A',
    );

    await deshacerYSubir();

    final local = (await ubicaciones.buscarEspacio('esp-b2'))!.espacio;
    expect(local.ubicacionId, _b);
    expect(local.numeroDepto, '2C');
    expect(enElServidor('espacio', 'esp-b2')['ubicacion_id'], _b);
    expect(
      enElServidor('espacio', 'esp-b2')['numero_depto'],
      '2C',
      reason: 'la edición no se pierde',
    );
    // El depto que nadie tocó vuelve a B en el teléfono y no se reenvía: el servidor ya lo tenía ahí.
    expect((await ubicaciones.buscarEspacio('esp-b3'))!.espacio.ubicacionId, _b);
    expect(enElServidor('espacio', 'esp-b3')['ubicacion_id'], _b);
    expect(await trabajosDe('espacio', 'esp-b3'), hasLength(1), reason: 'solo su alta');
    expect((await trabajoDeUnion()).state, 'INVALID', reason: 'no se reintenta');
  });

  test(
    '«Visita unión»: dada una visita y una entrevista nuevas de la persona de B después de unir, '
    'cuando el servidor rechaza la unión, van con ella a B en el teléfono y en el servidor, sin '
    'borrar nada',
    () async {
      await ubicaciones.insertar(_ubicacion(_a), espacio: _espacio('esp-a', _a));
      await ubicaciones.insertar(_ubicacion(_b, numero: '1236'), espacio: _espacio('esp-b', _b));
      await sembrarVinculo(db, id: 'ep-b', espacioId: 'esp-b', personaId: 'per-b');
      await sembrarVinculo(db, id: 'ep-a', espacioId: 'esp-a', personaId: 'per-a');
      await motor.syncNow();

      await unirEditarYRechazar(() async {
        await agendas.registrarVisita(
          visitaDe('vis-n', espacio: 'esp-a', vinculo: 'ep-b', creada: tDespues),
        );
        await agendas.agendar(
          agendaDe('ag-n', espacio: 'esp-a', vinculo: 'ep-b', creada: tDespues),
        );
        // La de la persona de A se queda en A.
        await agendas.agendar(
          agendaDe('ag-a', espacio: 'esp-a', vinculo: 'ep-a', creada: tDespues),
        );
      });
      expect(enElServidor('visita', 'vis-n')['espacio_id'], 'esp-a');
      expect(enElServidor('agenda', 'ag-n')['espacio_id'], 'esp-a');

      await deshacerYSubir();

      final visita = await (db.select(db.visitas)..where((v) => v.id.equals('vis-n'))).getSingle();
      expect(visita.espacioId, 'esp-b');
      expect(enElServidor('visita', 'vis-n')['espacio_id'], 'esp-b');
      expect(enElServidor('visita', 'vis-n')['espacio_persona_id'], 'ep-b');
      // La entrevista agendada y la agenda cumplida que nació con la visita espontánea.
      final deB = await (db.select(
        db.agendas,
      )..where((a) => a.espacioPersonaId.equals('ep-b'))).get();
      expect(deB, hasLength(2));
      for (final agenda in deB) {
        expect(agenda.espacioId, 'esp-b', reason: agenda.id);
        expect(enElServidor('agenda', agenda.id)['espacio_id'], 'esp-b', reason: agenda.id);
      }
      final deA = await (db.select(db.agendas)..where((a) => a.id.equals('ag-a'))).getSingle();
      expect(deA.espacioId, 'esp-a');
      expect(enElServidor('agenda', 'ag-a')['espacio_id'], 'esp-a');
      // Nada se borró.
      expect(await db.select(db.visitas).get(), hasLength(1));
      expect(await db.select(db.agendas).get(), hasLength(3));
      expect(servidor.rowsOf('agenda'), hasLength(3));
    },
  );
}
