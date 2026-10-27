// I1 (#178) de punta a punta, con el código real de los dos lados de la frontera: los DAOs de la
// app escriben en la DB Drift y encolan por `EncoladorSyncMotor`, el motor sube por un servidor
// falso que compara `sync_version` como el de verdad (§5.4), y lo que vuelve entra por
// `DriftLocalStore`.
import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/datos/encolador_sync_motor.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/jornada_local_data_source_drift.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/ubicacion_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/models/espacio_model.dart';
import 'package:colportores_mobile/features/mapa/data/models/ubicacion_model.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../helpers/campo_falsos.dart';
import '../../helpers/logger_mudo.dart';

const _ubi = 'ub-0000000000000000000000000001';

final _ubicacion = UbicacionModel.fromJson(const {
  'id': _ubi,
  'tipo': 'CASA',
  'calle': 'Rivera',
  'numero': '1234',
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

final _espacio = EspacioModel.fromJson(const {
  'id': 'esp-1',
  'ubicacion_id': _ubi,
  'numero_depto': null,
  'piso': null,
  'descripcion': null,
  'created_at': '2026-10-16T12:00:00.000Z',
  'updated_at': '2026-10-16T12:00:00.000Z',
  'created_by': 'col-1',
  'deleted_at': null,
  'sync_version': 0,
});

final _jornada = JornadaModel.fromJson(const {
  'id': 'jor-1',
  'colportor_id': 'col-1',
  'inicio': '2026-10-16T08:00:00.000Z',
  'fin': null,
  'acompaniante_id': null,
  'tipo_acompaniamiento': null,
  'total_visitas': 0,
  'total_ventas': 0,
  'created_at': '2026-10-16T08:00:00.000Z',
  'updated_at': '2026-10-16T08:00:00.000Z',
  'created_by': 'col-1',
  'deleted_at': null,
  'sync_version': 0,
});

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late FakeSyncTransport servidor;
  late SyncEngine motor;
  late UbicacionLocalDataSourceDrift ubicaciones;
  late JornadaLocalDataSourceDrift jornadas;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    servidor = FakeSyncTransport(pkFieldPorEntidad: const {'house_status': 'ubicacion_id'});
    motor = SyncEngine(
      specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
      transport: servidor,
      jobs: DriftJobStore(db),
      store: DriftLocalStore(db, entidades: entidadesQueEscribeElMotor),
    );
    final encolador = EncoladorSyncMotor(motor);
    ubicaciones = UbicacionLocalDataSourceDrift(db, encolador: encolador);
    jornadas = JornadaLocalDataSourceDrift(db, encolador: encolador);
  });
  tearDown(() async {
    await motor.dispose();
    await db.close();
  });

  Future<SyncStatus> cola() => DriftJobStore(db).status();

  test('el alta de una ubicación con su espacio se guarda, se encola y sube', () async {
    await ubicaciones.insertar(_ubicacion, espacio: _espacio);
    expect((await cola()).pending, 2);

    final resultado = await motor.syncNow();

    expect(resultado.ok, isTrue);
    expect(servidor.rowsOf('ubicacion').single['calle'], 'Rivera');
    expect(servidor.rowsOf('espacio').single['ubicacion_id'], _ubi);
    expect((await cola()).pending, 0);
    final local = await ubicaciones.obtener(_ubi);
    expect(local!.auditoria.syncVersion, 1, reason: 'la versión del servidor volvió a la fila');
  });

  test('si el alta se revierte, su job también: no sube una fila que no existe', () async {
    await ubicaciones.insertar(_ubicacion, espacio: _espacio);
    // Otra ubicación cuyo espacio choca por PK con el que ya está: la transacción del alta se
    // revierte después de haber encolado la ubicación.
    final otra = UbicacionModel.fromJson({..._ubicacion.toJson(), 'id': 'ub-2'});

    await expectLater(ubicaciones.insertar(otra, espacio: _espacio), throwsA(anything));

    expect((await cola()).pending, 2, reason: 'solo los dos jobs del alta que sí se guardó');
    expect(await ubicaciones.obtener('ub-2'), isNull);
  });

  test('modificar dos veces una ubicación que ya subió no choca con su propia versión', () async {
    await ubicaciones.insertar(_ubicacion);
    await motor.syncNow();

    var actual = (await ubicaciones.obtener(_ubi))!;
    for (final calle in ['Rivera 2', 'Rivera 3']) {
      actual = await ubicaciones.actualizar(
        UbicacionModel.fromJson({
          ...actual.toJson(),
          'calle': calle,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
        baseUpdatedAt: actual.auditoria.updatedAt,
      );
      final resultado = await motor.syncNow();
      expect(resultado.conflicts, 0, reason: 'si chocara, el LWW pisaría $calle');
    }

    expect(servidor.rowsOf('ubicacion').single['calle'], 'Rivera 3');
    expect((await ubicaciones.obtener(_ubi))!.calle, 'Rivera 3');
  });

  group('HU-UBI-004 · edición concurrente con sync entrante', () {
    /// Lo que el coordinador dejó en el servidor mientras el colportor editaba: la misma
    /// ubicación, una versión más y un `updated_at` posterior.
    Map<String, Object?> filaDelCoordinador({String calle = 'Rivera (coordinador)'}) => {
      ..._ubicacion.toJson(),
      'calle': calle,
      'updated_at': DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String(),
      'sync_version': 2,
    };

    Future<UbicacionModel> editarEnElTelefono(String calle) async {
      final actual = (await ubicaciones.obtener(_ubi))!;
      return ubicaciones.actualizar(
        UbicacionModel.fromJson({
          ...actual.toJson(),
          'calle': calle,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }),
        baseUpdatedAt: actual.auditoria.updatedAt,
      );
    }

    test(
      'dado que el coordinador editó la ubicación y llega después de mi edición local, cuando '
      'sincroniza, queda la fila del servidor, la cola se vacía y la versión se reconcilia',
      () async {
        await ubicaciones.insertar(_ubicacion);
        await motor.syncNow();
        servidor.seed('ubicacion', [filaDelCoordinador()]);

        await editarEnElTelefono('Rivera (colportor)');
        final resultado = await motor.syncNow();

        expect(resultado.conflicts, 1, reason: 'el servidor tiene una versión más nueva (§5.4)');
        expect((await cola()).pending, 0, reason: 'el job se cierra: no es un error del colportor');
        final local = (await ubicaciones.obtener(_ubi))!;
        expect(local.calle, 'Rivera (coordinador)');
        expect(
          local.auditoria.syncVersion,
          2,
          reason: 'la versión local alcanza a la del servidor',
        );
        expect(servidor.rowsOf('ubicacion').single['calle'], 'Rivera (coordinador)');
      },
    );

    test('dado el conflicto resuelto, cuando el colportor repite su corrección sobre la fila '
        'nueva, sube sin chocar', () async {
      await ubicaciones.insertar(_ubicacion);
      await motor.syncNow();
      servidor.seed('ubicacion', [filaDelCoordinador()]);
      await editarEnElTelefono('Rivera (colportor)');
      await motor.syncNow();

      await editarEnElTelefono('Rivera 5678');
      final resultado = await motor.syncNow();

      expect(resultado.conflicts, 0);
      expect((await cola()).pending, 0);
      expect(servidor.rowsOf('ubicacion').single['calle'], 'Rivera 5678');
      expect((await ubicaciones.obtener(_ubi))!.auditoria.syncVersion, 3);
    });

    test('dado que edito sin señal y el coordinador también, cuando vuelve la red, el conflicto '
        'se resuelve igual y la edición no se pierde en silencio', () async {
      await ubicaciones.insertar(_ubicacion);
      await motor.syncNow();
      servidor.offline();
      await editarEnElTelefono('Rivera (colportor)');
      expect((await motor.syncNow()).ok, isFalse);
      expect((await cola()).pending, 1, reason: 'sin red la edición espera en la cola');
      servidor.seed('ubicacion', [filaDelCoordinador()]);

      servidor.online();
      final resultado = await motor.syncNow();

      expect(resultado.conflicts, 1);
      expect((await cola()).pending, 0);
      expect((await ubicaciones.obtener(_ubi))!.calle, 'Rivera (coordinador)');
    });
  });

  test('la jornada sube al iniciarla y al cerrarla, y no se reabre en el teléfono', () async {
    await jornadas.insertar(_jornada);
    await motor.syncNow();
    expect(servidor.rowsOf('jornada').single['fin'], isNull);

    final fin = DateTime.utc(2026, 10, 16, 20);
    await jornadas.finalizar(
      JornadaModel.fromJson({
        ..._jornada.toJson(),
        'fin': fin.toIso8601String(),
        'updated_at': fin.toIso8601String(),
      }),
    );
    final resultado = await motor.syncNow();

    expect(resultado.conflicts, 0);
    expect(servidor.rowsOf('jornada').single['fin'], fin.toIso8601String());
    expect(await jornadas.obtenerActiva('col-1'), isNull, reason: 'el LWW la habría reabierto');
  });

  test('una jornada iniciada y cerrada sin señal sube como una sola alta', () async {
    await jornadas.insertar(_jornada);
    final fin = DateTime.utc(2026, 10, 16, 20);
    await jornadas.finalizar(
      JornadaModel.fromJson({
        ..._jornada.toJson(),
        'fin': fin.toIso8601String(),
        'updated_at': fin.toIso8601String(),
      }),
    );

    expect((await cola()).pending, 1, reason: 'el cierre se fundió en el alta sin mandar');
    await motor.syncNow();
    expect(servidor.rowsOf('jornada').single['fin'], fin.toIso8601String());
  });

  test('sin red, todo queda en la cola y sube cuando vuelve', () async {
    servidor.offline();
    await jornadas.insertar(_jornada);
    await ubicaciones.insertar(_ubicacion, espacio: _espacio);

    final sinRed = await motor.syncNow();
    expect(sinRed.ok, isFalse);
    expect((await cola()).pending, 3);

    servidor.online();
    await motor.syncNow();
    expect((await cola()).pending, 0);
    expect(servidor.rowsOf('jornada'), hasLength(1));
  });

  group('la agenda y las visitas (BACK-HU-VIS-001)', () {
    late AgendaLocalDataSourceDrift agenda;

    setUp(() async {
      final encolador = EncoladorSyncMotor(motor);
      agenda = AgendaLocalDataSourceDrift(
        db,
        encolador: encolador,
        estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
      );
      await sembrarCasa(db);
    });

    test(
      'agendar y registrar la visita suben: la agenda cumplida, la visita y el color de la casa',
      () async {
        await agenda.agendar(agendaDe('age-1', esEstricta: true), nota: notaDe('nota-1'));
        await agenda.registrarVisita(visitaDe('vis-1', creada: t0), agendaId: 'age-1');

        final resultado = await motor.syncNow();

        expect(resultado.ok, isTrue);
        expect(resultado.conflicts, 0);
        expect((await cola()).pending, 0);
        final subida = servidor.rowsOf('agenda').single;
        expect(subida['estado'], 'CUMPLIDA');
        expect(subida['visita_id'], 'vis-1');
        expect(subida['es_estricta'], true);
        expect(servidor.rowsOf('visita').single['tipo_resultado'], 'ENTREVISTA');
        final casa = servidor.rowsOf('house_status').single;
        expect(casa['ubicacion_id'], 'ub-1');
        expect(casa['color'], 'ENTREVISTA_SIN_VENTA');
        expect(casa['prioridad'], 5);
        final todo = '${servidor.rowsOf('agenda')}${servidor.rowsOf('visita')}$casa';
        expect(todo, isNot(contains('Atiende')), reason: 'la nota es local-only (ADR-017)');
      },
    );

    test(
      'la visita espontánea sube con su agenda CUMPLIDA: la visita primero y sin conflictos',
      () async {
        await agenda.registrarVisita(visitaDe('vis-1', creada: t0));

        final resultado = await motor.syncNow();

        expect(resultado.ok, isTrue);
        expect(resultado.conflicts, 0);
        expect((await cola()).pending, 0);
        final subida = servidor.rowsOf('agenda').single;
        expect(subida['estado'], 'CUMPLIDA');
        expect(subida['tipo'], 'ENTREVISTA');
        expect(subida['visita_id'], 'vis-1');
        expect(servidor.rowsOf('visita').single['id'], 'vis-1');
      },
    );

    test('cancelar la única agenda de una casa baja su fila de la cache con un delete', () async {
      await agenda.agendar(agendaDe('age-1'));
      await motor.syncNow();
      expect(servidor.rowsOf('house_status').single['deleted_at'], isNull);

      await agenda.cancelar('age-1', ahora: t0.add(const Duration(minutes: 1)));
      final resultado = await motor.syncNow();

      expect(resultado.conflicts, 0);
      expect(servidor.rowsOf('agenda').single['estado'], 'CANCELADA');
      expect(servidor.rowsOf('house_status'), isEmpty, reason: 'la fila se dio de baja');
    });

    test('la casa que vuelve a «Sin visita» y se vuelve a pintar sube viva y sin conflictos '
        '(agendar, sync, cancelar, sync, re-agendar, sync)', () async {
      await agenda.agendar(agendaDe('age-1'));
      expect((await motor.syncNow()).conflicts, 0);

      await agenda.cancelar('age-1', ahora: t0.add(const Duration(minutes: 1)));
      expect((await motor.syncNow()).conflicts, 0);
      expect(servidor.rowsOf('house_status'), isEmpty, reason: 'la baja subió');
      expect(
        (await db.select(db.houseStatuses).getSingle()).syncVersion,
        2,
        reason: 'el delete aceptado devolvió su versión a la fila local',
      );

      await agenda.agendar(agendaDe('age-2', creada: t0.add(const Duration(minutes: 2))));
      final resultado = await motor.syncNow();

      expect(resultado.ok, isTrue);
      expect(resultado.conflicts, 0);
      expect((await cola()).pending, 0);
      final casa = servidor.rowsOf('house_status').single;
      expect(casa['color'], 'ENTREVISTA_PROGRAMADA');
      expect(casa['deleted_at'], isNull);
      final local = await db.select(db.houseStatuses).getSingle();
      expect([local.color, local.deletedAt, local.syncVersion], ['ENTREVISTA_PROGRAMADA', null, 3]);
    });

    test('lo mismo sin sync entre medio: cancelar y re-agendar antes de subir', () async {
      await agenda.agendar(agendaDe('age-1'));
      await motor.syncNow();

      await agenda.cancelar('age-1', ahora: t0.add(const Duration(minutes: 1)));
      await agenda.agendar(agendaDe('age-2', creada: t0.add(const Duration(minutes: 2))));
      final resultado = await motor.syncNow();

      expect(resultado.ok, isTrue);
      expect(resultado.conflicts, 0);
      expect((await cola()).pending, 0);
      expect(servidor.rowsOf('house_status').single['color'], 'ENTREVISTA_PROGRAMADA');
    });

    test('una baja que vuelve a pintarse con otro color tampoco choca', () async {
      await agenda.agendar(agendaDe('age-1'));
      await motor.syncNow();
      await agenda.cancelar('age-1', ahora: t0.add(const Duration(minutes: 1)));
      await motor.syncNow();

      await agenda.registrarVisita(visitaDe('vis-1', creada: t0.add(const Duration(minutes: 2))));
      final resultado = await motor.syncNow();

      expect(resultado.conflicts, 0);
      expect(servidor.rowsOf('house_status').single['color'], 'ENTREVISTA_SIN_VENTA');
    });

    test('sin red, todo queda en la cola y sube cuando vuelve, en orden', () async {
      servidor.offline();
      await agenda.agendar(agendaDe('age-1'));
      await agenda.registrarVisita(
        visitaDe('vis-1', creada: t0.add(const Duration(minutes: 1))),
        agendaId: 'age-1',
      );

      expect((await motor.syncNow()).ok, isFalse);
      servidor.online();
      final resultado = await motor.syncNow();

      expect(resultado.ok, isTrue);
      expect((await cola()).pending, 0);
      expect(servidor.rowsOf('agenda').single['estado'], 'CUMPLIDA');
      expect(servidor.rowsOf('house_status').single['color'], 'ENTREVISTA_SIN_VENTA');
    });
  });
}
