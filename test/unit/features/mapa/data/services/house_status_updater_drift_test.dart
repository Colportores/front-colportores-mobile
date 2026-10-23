// El servicio de la cache `house_status` (ADR-003, R-UB08) contra las tablas reales: AppDatabase en
// memoria, mismo esquema y mismos CHECK que en el dispositivo.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/encolador_sync.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/color_house_status.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

typedef _C = ColorHouseStatus;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late HouseStatusUpdaterDrift updater;
  final t1 = t0.add(const Duration(minutes: 5));

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    updater = HouseStatusUpdaterDrift(db, encolador: encolador);
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  Future<void> recalcular({DateTime? ahora, String ubicacion = 'ub-1'}) =>
      updater.recalcular(ubicacion, ahora: ahora ?? t0, colportorId: 'col-1');

  Future<List<HouseStatusFila>> filas() => db.select(db.houseStatuses).get();

  group('dado una casa sin nada', () {
    test(
      'cuando se recalcula, no hay fila ni job: es «Sin visita» (la ausencia de fila)',
      () async {
        final estado = await updater.recalcular('ub-1', ahora: t0, colportorId: 'col-1');

        expect(estado, isNull);
        expect(await filas(), isEmpty);
        expect(encolador.encolados, isEmpty);
      },
    );
  });

  group('dado lo que pasó en la casa', () {
    test(
      'una agenda de entrevista pendiente: crea la fila en 3 y encola el insert sin PII',
      () async {
        await insertarAgenda(db, agendaDe('age-1'));

        final estado = await updater.recalcular('ub-1', ahora: t1, colportorId: 'col-9');

        expect(estado!.color, _C.entrevistaProgramada);
        final fila = (await filas()).single;
        expect(fila.color, 'ENTREVISTA_PROGRAMADA');
        expect(fila.prioridad, 3);
        expect(fila.lat, -34.9);
        expect(fila.lon, -56.16);
        expect(fila.tipoUbicacion, 'CASA');
        expect(fila.createdAt, t1);
        expect(fila.createdBy, 'col-9');
        final job = encolador.encolados.single;
        expect(job.entidad, 'house_status');
        expect(job.operacion, OperacionSync.insert);
        expect(job.payload.keys.toSet(), {
          'ubicacion_id',
          'lat',
          'lon',
          'tipo_ubicacion',
          'color',
          'prioridad',
          'created_at',
          'updated_at',
          'created_by',
          'deleted_at',
          'sync_version',
        });
        expect(job.payload['ubicacion_id'], 'ub-1');
        expect(job.payload['color'], 'ENTREVISTA_PROGRAMADA');
        expect(job.payload['prioridad'], 3);
        expect(job.payload['tipo_ubicacion'], 'CASA');
      },
    );

    test('una agenda de cobranza pendiente: no pinta nada', () async {
      await insertarAgenda(db, agendaDe('age-1', tipo: TipoAgenda.cobranza));

      await recalcular();

      expect(await filas(), isEmpty);
    });

    test('una agenda cumplida, cancelada o dada de baja: no cuenta', () async {
      await insertarAgenda(db, agendaDe('age-1', estado: EstadoAgenda.completada));
      await insertarAgenda(db, agendaDe('age-2', estado: EstadoAgenda.cancelada));
      await insertarAgenda(db, agendaDe('age-3', borrada: t1));

      await recalcular();

      expect(await filas(), isEmpty);
    });

    test('cada resultado de visita da su color, y la venta todavía no pinta', () async {
      final esperado = {
        TipoResultadoVisita.entrevista: 'ENTREVISTA_SIN_VENTA',
        TipoResultadoVisita.noContesto: 'SIN_CONTESTAR',
        TipoResultadoVisita.rechazo: 'RECHAZO',
      };
      for (final MapEntry(key: resultado, value: color) in esperado.entries) {
        await db.delete(db.visitas).go();
        await db.delete(db.houseStatuses).go();
        await insertarVisita(db, visitaDe('vis-1', resultado: resultado));

        await recalcular();

        expect((await filas()).single.color, color, reason: resultado.name);
      }

      await db.delete(db.visitas).go();
      await db.delete(db.houseStatuses).go();
      await insertarVisita(db, visitaDe('vis-1', resultado: TipoResultadoVisita.venta));
      await recalcular();
      expect(await filas(), isEmpty);
    });

    test('una visita dada de baja no cuenta', () async {
      await insertarVisita(db, visitaDe('vis-1', borrada: t1));

      await recalcular();

      expect(await filas(), isEmpty);
    });

    test(
      'una agenda pendiente y un rechazo: gana la agenda, aunque el rechazo sea más nuevo',
      () async {
        await insertarAgenda(db, agendaDe('age-1'));
        await insertarVisita(
          db,
          visitaDe('vis-1', resultado: TipoResultadoVisita.rechazo, creada: t1),
        );

        await recalcular(ahora: t1);

        expect((await filas()).single.color, 'ENTREVISTA_PROGRAMADA');
      },
    );
  });

  group('dado que la fila ya existe', () {
    test('y nada cambió: no escribe ni encola de nuevo', () async {
      await insertarAgenda(db, agendaDe('age-1'));
      await recalcular();
      encolador.encolados.clear();

      final estado = await updater.recalcular('ub-1', ahora: t1, colportorId: 'col-1');

      expect(estado!.color, _C.entrevistaProgramada);
      expect(encolador.encolados, isEmpty);
      expect((await filas()).single.updatedAt, t0, reason: 'no tocó la fila');
    });

    test('y cambió el color: actualiza la fila y encola un update con su sync_version', () async {
      await insertarAgenda(db, agendaDe('age-1'));
      await recalcular();
      await (db.update(db.houseStatuses)..where((h) => h.ubicacionId.equals('ub-1'))).write(
        const HouseStatusesCompanion(syncVersion: Value(4)),
      );
      encolador.encolados.clear();
      await (db.update(
        db.agendas,
      )).write(AgendasCompanion(estado: Value(EstadoAgenda.completada.codigo)));
      await insertarVisita(db, visitaDe('vis-1', resultado: TipoResultadoVisita.noContesto));

      await updater.recalcular('ub-1', ahora: t1, colportorId: 'col-1');

      final fila = (await filas()).single;
      expect(fila.color, 'SIN_CONTESTAR');
      expect(fila.prioridad, 6);
      expect(fila.updatedAt, t1);
      expect(fila.createdAt, t0, reason: 'la fila es la misma');
      final job = encolador.encolados.single;
      expect(job.operacion, OperacionSync.update);
      expect(job.payload['color'], 'SIN_CONTESTAR');
      expect(job.payload['sync_version'], 4);
    });

    test('y la casa se quedó sin ningún estado: da de baja la fila y encola el delete', () async {
      await insertarAgenda(db, agendaDe('age-1'));
      await recalcular();
      encolador.encolados.clear();
      await (db.update(
        db.agendas,
      )).write(AgendasCompanion(estado: Value(EstadoAgenda.cancelada.codigo)));

      final estado = await updater.recalcular('ub-1', ahora: t1, colportorId: 'col-1');

      expect(estado, isNull);
      final fila = (await filas()).single;
      expect(fila.deletedAt, t1);
      final job = encolador.encolados.single;
      expect(job.operacion, OperacionSync.delete);
      expect(job.payload['deleted_at'], t1.toIso8601String());
    });

    test('y ya estaba dada de baja sin estados: no la vuelve a dar de baja', () async {
      await insertarAgenda(db, agendaDe('age-1'));
      await recalcular();
      await (db.update(
        db.agendas,
      )).write(AgendasCompanion(estado: Value(EstadoAgenda.cancelada.codigo)));
      await recalcular(ahora: t1);
      encolador.encolados.clear();

      await recalcular(ahora: t1.add(const Duration(hours: 1)));

      expect(encolador.encolados, isEmpty);
      expect((await filas()).single.deletedAt, t1);
    });

    test(
      'y la casa vuelve a tener un estado: la reaviva con un update y deleted_at en null',
      () async {
        await insertarAgenda(db, agendaDe('age-1'));
        await recalcular();
        await (db.update(
          db.agendas,
        )).write(AgendasCompanion(estado: Value(EstadoAgenda.cancelada.codigo)));
        await recalcular(ahora: t1);
        encolador.encolados.clear();
        await insertarVisita(db, visitaDe('vis-1', resultado: TipoResultadoVisita.rechazo));
        final t2 = t1.add(const Duration(hours: 1));

        await recalcular(ahora: t2);

        final fila = (await filas()).single;
        expect(fila.deletedAt, isNull);
        expect(fila.color, 'RECHAZO');
        expect(fila.updatedAt, t2);
        expect(encolador.encolados.single.operacion, OperacionSync.update);
        expect(encolador.encolados.single.payload['deleted_at'], isNull);
      },
    );

    test(
      'y la ubicación cambió de punto o de tipo: la fila lo copia aunque el color sea el mismo',
      () async {
        await insertarAgenda(db, agendaDe('age-1'));
        await recalcular();
        encolador.encolados.clear();
        await (db.update(db.ubicaciones)).write(
          const UbicacionesCompanion(lat: Value(-34.5), lon: Value(-56.5), tipo: Value('NEGOCIO')),
        );

        await recalcular(ahora: t1);

        final fila = (await filas()).single;
        expect([fila.lat, fila.lon, fila.tipoUbicacion], [-34.5, -56.5, 'NEGOCIO']);
        expect(encolador.encolados.single.operacion, OperacionSync.update);
      },
    );
  });

  group('dado un edificio', () {
    setUp(() async {
      await db.close();
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      encolador = EncoladorSyncEnMemoria();
      updater = HouseStatusUpdaterDrift(db, encolador: encolador);
      await sembrarEdificio(db);
    });

    test('el color sale de todos sus deptos: una fila por ubicación, no por depto', () async {
      await insertarAgenda(db, agendaDe('age-1'));
      await insertarVisita(
        db,
        visitaDe('vis-1', vinculo: 'ep-2', resultado: TipoResultadoVisita.rechazo),
      );

      await recalcular();

      expect((await filas()).single.color, 'ENTREVISTA_PROGRAMADA');
      expect((await filas()).single.tipoUbicacion, 'EDIFICIO');
    });

    test('un depto dado de baja no pinta el edificio', () async {
      await insertarVisita(
        db,
        visitaDe('vis-1', vinculo: 'ep-2', resultado: TipoResultadoVisita.entrevista),
      );
      await (db.update(
        db.espacios,
      )..where((e) => e.id.equals('esp-2'))).write(EspaciosCompanion(deletedAt: Value(t1)));

      await recalcular();

      expect(await filas(), isEmpty);
    });

    test('un vínculo dado de baja en un depto activo sigue contando: la visita ya pasó', () async {
      await insertarVisita(db, visitaDe('vis-1', resultado: TipoResultadoVisita.noContesto));
      await (db.update(
        db.espacioPersonas,
      )..where((v) => v.id.equals('ep-1'))).write(EspacioPersonasCompanion(deletedAt: Value(t1)));

      await recalcular();

      expect((await filas()).single.color, 'SIN_CONTESTAR');
    });
  });

  group('dado una ubicación que no se puede pintar', () {
    test('que no está en el teléfono: no escribe nada', () async {
      final estado = await updater.recalcular('ub-inexistente', ahora: t0, colportorId: 'col-1');

      expect(estado, isNull);
      expect(await filas(), isEmpty);
      expect(encolador.encolados, isEmpty);
    });

    test('que está dada de baja: no la toca, aunque tenga una agenda pendiente', () async {
      await insertarAgenda(db, agendaDe('age-1'));
      await (db.update(db.ubicaciones)).write(UbicacionesCompanion(deletedAt: Value(t1)));

      final estado = await updater.recalcular('ub-1', ahora: t1, colportorId: 'col-1');

      expect(estado, isNull);
      expect(await filas(), isEmpty);
      expect(encolador.encolados, isEmpty);
    });
  });

  group('dado un fallo', () {
    test('del encolado: la transacción se revierte y no queda la fila de la cache', () async {
      await insertarAgenda(db, agendaDe('age-1'));
      encolador.fallarCon = StateError('motor apagado');

      await expectLater(recalcular(), throwsStateError);

      expect(await filas(), isEmpty);
    });
  });

  group('la tabla house_status', () {
    test('copia el CHECK del servidor: un color con otra prioridad no entra', () async {
      Future<void> insertar(String color, int prioridad) => db
          .into(db.houseStatuses)
          .insert(
            HouseStatusesCompanion.insert(
              ubicacionId: 'ub-1',
              lat: -34.9,
              lon: -56.16,
              tipoUbicacion: 'CASA',
              color: color,
              prioridad: prioridad,
              createdAt: t0,
              updatedAt: t0,
            ),
          );

      await expectLater(insertar('RECHAZO', 3), throwsA(anything));
      await expectLater(insertar('INVENTADO', 3), throwsA(anything));
      await expectLater(insertar('RECHAZO', 8), throwsA(anything));
      await insertar('RECHAZO', 7);

      expect(await filas(), hasLength(1));
    });

    test('guarda una sola fila por ubicación (la clave es ubicacion_id)', () async {
      Future<void> insertar() => db
          .into(db.houseStatuses)
          .insert(
            HouseStatusesCompanion.insert(
              ubicacionId: 'ub-1',
              lat: -34.9,
              lon: -56.16,
              tipoUbicacion: 'CASA',
              color: 'RECHAZO',
              prioridad: 7,
              createdAt: t0,
              updatedAt: t0,
            ),
          );

      await insertar();
      await expectLater(insertar(), throwsA(anything));
    });
  });
}
