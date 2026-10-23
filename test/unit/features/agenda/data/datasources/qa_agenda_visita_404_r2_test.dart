// QA r2 de BACK-HU-VIS-001 (#404): lo que cambió tras la ronda 1 de la revisión y la decisión de QA
// P1. (a) Una visita sobre una agenda que no sirve se guarda como espontánea y la agenda queda como
// estaba; (b) la casa que vuelve a «Sin visita» y se repinta sube bien con el motor real, en
// cualquier orden de acciones y de syncs, sin conflictos.
import 'dart:convert';
import 'dart:math';

import 'package:colportores_mobile/catalogo.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/datos/drift_job_store.dart';
import 'package:colportores_mobile/datos/drift_local_store.dart';
import 'package:colportores_mobile/datos/encolador_sync_motor.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/agenda_repository_impl.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita_guardada.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('visita sobre una agenda que no sirve: se guarda igual, sin tocar la agenda', () {
    late AppDatabase db;
    late EncoladorSyncEnMemoria encolador;
    late AgendaRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      encolador = EncoladorSyncEnMemoria();
      repo = AgendaRepositoryImpl(
        AgendaLocalDataSourceDrift(
          db,
          encolador: encolador,
          estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
        ),
        logger: loggerMudo(),
      );
      await sembrarEdificio(db);
    });
    tearDown(() => db.close());

    Future<String> agendaComoEstaba(String id) async => jsonEncode(
      (await (db.select(db.agendas)..where((a) => a.id.equals(id))).getSingle()).toJson(),
    );

    Future<VisitaGuardada> registrar({
      String? agendaId,
      String vinculo = 'ep-1',
      String id = 'vis-1',
    }) async {
      final r = await repo.registrarVisita(
        visitaDe(
          id,
          vinculo: vinculo,
          resultado: TipoResultadoVisita.rechazo,
          creada: t0.add(const Duration(minutes: 9)),
        ),
        agendaId: agendaId,
        nota: notaDe('not-$id', texto: 'no quiere que vuelvan'),
      );
      return r.fold((f) => fail('debía guardarse: $f'), (v) => v);
    }

    void guardadaSinAgenda(VisitaGuardada r, MotivoAgendaIgnorada motivo) {
      expect(r.agendaIgnorada, motivo);
      expect(r.aviso, motivo.aviso);
      expect(
        r.aviso,
        contains('guardamos la visita igual'),
        reason: 'dice qué pasó y que no se perdió',
      );
    }

    test('agenda cancelada: la visita queda con su nota y su color, la agenda no cambia', () async {
      await repo.agendar(agendaDe('age-1'));
      await repo.cancelar('age-1', ahora: t0.add(const Duration(minutes: 1)));
      final antes = await agendaComoEstaba('age-1');
      final cola = encolador.encolados.length;

      final r = await registrar(agendaId: 'age-1');

      guardadaSinAgenda(r, MotivoAgendaIgnorada.cerrada);
      expect(await agendaComoEstaba('age-1'), antes);
      expect(
        encolador.encolados.skip(cola).map((c) => '${c.entidad}:${c.operacion.name}'),
        ['visita:insert', 'agenda:insert', 'house_status:update'],
        reason: 'la cancelada no se vuelve a encolar: solo nace la agenda cumplida de la visita',
      );
      final nueva = (await db.select(db.agendas).get()).singleWhere((a) => a.id != 'age-1');
      expect([nueva.estado, nueva.visitaId], ['COMPLETADA', 'vis-1']);
      expect((await db.select(db.houseStatuses).getSingle()).color, 'RECHAZO');
      final nota = (await db.select(db.notas).get()).single;
      expect((nota.targetType, nota.targetId), ('VISITA', 'vis-1'));
    });

    test('agenda ya cumplida por otra visita: la segunda se guarda sin vincular y no pisa a la '
        'primera', () async {
      await repo.agendar(agendaDe('age-1'));
      await registrar(agendaId: 'age-1', id: 'vis-1');
      final antes = await agendaComoEstaba('age-1');

      final r = await registrar(agendaId: 'age-1', id: 'vis-2');

      guardadaSinAgenda(r, MotivoAgendaIgnorada.cerrada);
      expect(await agendaComoEstaba('age-1'), antes);
      final agendas = await db.select(db.agendas).get();
      expect(agendas.singleWhere((a) => a.id == 'age-1').visitaId, 'vis-1');
      expect(
        agendas.singleWhere((a) => a.id != 'age-1').visitaId,
        'vis-2',
        reason: 'la segunda nace con su agenda cumplida',
      );
      expect((await db.select(db.visitas).get()).map((v) => v.id).toSet(), {'vis-1', 'vis-2'});
    });

    test('agenda que no existe: se guarda y avisa', () async {
      guardadaSinAgenda(
        await registrar(agendaId: 'age-fantasma'),
        MotivoAgendaIgnorada.inexistente,
      );
      final agenda = (await db.select(db.agendas).get()).single;
      expect(
        [agenda.estado, agenda.visitaId],
        ['COMPLETADA', 'vis-1'],
        reason: 'la espontánea nace con su agenda cumplida, no con la fantasma',
      );
      expect((await db.select(db.visitas).get()).length, 1);
    });

    test('agenda dada de baja: cuenta como inexistente', () async {
      await insertarAgenda(db, agendaDe('age-b', borrada: t0));
      guardadaSinAgenda(await registrar(agendaId: 'age-b'), MotivoAgendaIgnorada.inexistente);
      final agendas = await db.select(db.agendas).get();
      expect(agendas.singleWhere((a) => a.id == 'age-b').estado, 'PENDIENTE');
      expect(agendas.singleWhere((a) => a.id != 'age-b').estado, 'COMPLETADA');
    });

    test('agenda de otra persona: se guarda y la agenda sigue pendiente', () async {
      await repo.agendar(agendaDe('age-2', vinculo: 'ep-2'));
      final antes = await agendaComoEstaba('age-2');

      final r = await registrar(agendaId: 'age-2', vinculo: 'ep-1');

      guardadaSinAgenda(r, MotivoAgendaIgnorada.deOtraPersona);
      expect(await agendaComoEstaba('age-2'), antes);
      expect(
        (await db.select(db.houseStatuses).getSingle()).color,
        'ENTREVISTA_PROGRAMADA',
        reason: 'la agenda pendiente de la casa manda sobre el rechazo (prioridad 3 < 7)',
      );
    });

    test('un vínculo que no está en el teléfono sigue rechazando', () async {
      final r = await repo.registrarVisita(visitaDe('vis-x', vinculo: 'ep-que-no-existe'));
      expect(r.isLeft(), isTrue);
      expect(await db.select(db.visitas).get(), isEmpty);
    });

    test('sin agendaId no hay aviso', () async {
      final r = await registrar();
      expect(r.agendaIgnorada, isNull);
      expect(r.aviso, isNull);
    });

    test('los avisos dicen qué pasó, no traen ids y son cortos', () {
      for (final m in MotivoAgendaIgnorada.values) {
        expect(m.aviso, isNot(contains('age-')));
        expect(m.aviso.length, lessThan(120));
      }
    });
  });

  group('la casa que vuelve a «Sin visita» y se repinta, con el motor real', () {
    late AppDatabase db;
    late FakeSyncTransport servidor;
    late SyncEngine motor;
    late AgendaRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      servidor = FakeSyncTransport(pkFieldPorEntidad: const {'house_status': 'ubicacion_id'});
      motor = SyncEngine(
        specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
        transport: servidor,
        jobs: DriftJobStore(db),
        store: DriftLocalStore(db, entidades: entidadesQueEscribeElMotor),
      );
      final encolador = EncoladorSyncMotor(motor);
      repo = AgendaRepositoryImpl(
        AgendaLocalDataSourceDrift(
          db,
          encolador: encolador,
          estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
        ),
        logger: loggerMudo(),
      );
      await sembrarCasa(db);
    });
    tearDown(() async {
      await motor.dispose();
      await db.close();
    });

    for (final semilla in List.generate(10, (i) => 700 + i)) {
      test('agendar, cancelar y visitar en cualquier orden, con syncs en cualquier momento '
          '(semilla $semilla)', () async {
        final azar = Random(semilla);
        var minuto = 0;
        DateTime ahora() => t0.add(Duration(minutes: ++minuto));
        final agendas = <String>[];
        var n = 0;
        var conflictos = 0;

        for (var paso = 0; paso < 24; paso++) {
          switch (azar.nextInt(4)) {
            case 0:
              final id = 'age-${++n}';
              agendas.add(id);
              await repo.agendar(agendaDe(id, creada: ahora()));
            case 1:
              if (agendas.isNotEmpty) {
                await repo.cancelar(agendas[azar.nextInt(agendas.length)], ahora: ahora());
              }
            case 2:
              await repo.registrarVisita(
                visitaDe(
                  'vis-${++n}',
                  resultado: TipoResultadoVisita.values[1 + azar.nextInt(3)],
                  creada: ahora(),
                ),
                agendaId: agendas.isEmpty || azar.nextBool()
                    ? null
                    : agendas[azar.nextInt(agendas.length)],
              );
            default:
              final r = await motor.syncNow();
              conflictos += r.conflicts;
              expect(r.ok, isTrue, reason: 'paso $paso');
          }
        }
        final fin = await motor.syncNow();
        conflictos += fin.conflicts;

        expect(conflictos, 0, reason: 'ningún conflicto en toda la secuencia');
        expect((await DriftJobStore(db).status()).pending, 0);
        final local = await db.select(db.houseStatuses).getSingleOrNull();
        final enServidor = servidor.rowsOf('house_status');
        if (local == null || local.deletedAt != null) {
          expect(enServidor, isEmpty, reason: 'casa sin estado: no hay fila viva arriba');
        } else {
          expect(enServidor.single['color'], local.color);
          expect(enServidor.single['deleted_at'], isNull);
        }
        for (final a in await db.select(db.agendas).get()) {
          final arriba = servidor.rowsOf('agenda').where((f) => f['id'] == a.id).single;
          expect(arriba['estado'], a.estado, reason: a.id);
          expect(a.estado, isIn(EstadoAgenda.values.map((e) => e.codigo)));
        }
        expect(servidor.rowsOf('visita').length, (await db.select(db.visitas).get()).length);
      });
    }
  });

  group('la visita espontánea nace con su agenda cumplida: todo o nada, una sola vez', () {
    late AppDatabase db;
    late EncoladorSyncEnMemoria encolador;
    late AgendaRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      encolador = EncoladorSyncEnMemoria();
      repo = AgendaRepositoryImpl(
        AgendaLocalDataSourceDrift(
          db,
          encolador: encolador,
          estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
        ),
        logger: loggerMudo(),
      );
      await sembrarCasa(db);
    });
    tearDown(() => db.close());

    Future<List<String>> filas() async => [
      for (final a in await db.select(db.agendas).get()) 'a:${a.id}:${a.estado}:${a.visitaId}',
      for (final v in await db.select(db.visitas).get()) 'v:${v.id}',
      for (final h in await db.select(db.houseStatuses).get()) 'h:${h.color}:${h.deletedAt}',
      for (final n in await db.select(db.notas).get()) 'n:${n.id}',
    ];

    // La espontánea encola 3 jobs: la visita, su agenda y el color de la casa.
    for (final n in [0, 1, 2]) {
      test('si el encolado falla en el job $n no queda nada, y el reintento deja una sola agenda '
          'y una sola visita', () async {
        encolador
          ..fallarCon = StateError('motor apagado')
          ..fallarDespuesDe = n;
        final visita = visitaDe(
          'vis-1',
          resultado: TipoResultadoVisita.noContesto,
          creada: t0.add(const Duration(minutes: 3)),
        );

        final r = await repo.registrarVisita(visita, nota: notaDe('not-1'));

        expect(r.isLeft(), isTrue);
        expect(await filas(), isEmpty);

        encolador.fallarCon = null;
        expect((await repo.registrarVisita(visita, nota: notaDe('not-1'))).isRight(), isTrue);
        final agendas = await db.select(db.agendas).get();
        expect(agendas.map((a) => (a.estado, a.visitaId)), [('COMPLETADA', 'vis-1')]);
        expect((await db.select(db.visitas).get()).length, 1);
        expect((await db.select(db.houseStatuses).getSingle()).color, 'SIN_CONTESTAR');
      });
    }

    test('el mismo envío dos veces a la vez (doble tap) deja una visita y una agenda', () async {
      final visita = visitaDe('vis-1', creada: t0.add(const Duration(minutes: 3)));

      final rs = await Future.wait([repo.registrarVisita(visita), repo.registrarVisita(visita)]);

      expect(rs.every((r) => r.isRight()), isTrue);
      expect((await db.select(db.visitas).get()).length, 1);
      expect((await db.select(db.agendas).get()).length, 1);
      expect(encolador.encolados.where((c) => c.entidad == 'agenda').length, 1);
    });

    test('el mismo envío otra vez, ya guardado, no suma otra agenda ni otro job', () async {
      final visita = visitaDe('vis-1', creada: t0.add(const Duration(minutes: 3)));
      await repo.registrarVisita(visita);
      final cola = encolador.encolados.length;

      final otra = await repo.registrarVisita(visita);

      expect(otra.isRight(), isTrue);
      expect((await db.select(db.agendas).get()).length, 1);
      expect(encolador.encolados.length, cola);
    });

    test('cada espontánea tiene su agenda y su agenda es de su visita, sin pintar la casa por sí '
        'sola', () async {
      await repo.registrarVisita(
        visitaDe('vis-1', resultado: TipoResultadoVisita.venta, creada: t0),
      );
      await repo.registrarVisita(
        visitaDe(
          'vis-2',
          resultado: TipoResultadoVisita.venta,
          creada: t0.add(const Duration(minutes: 1)),
        ),
      );

      final agendas = await db.select(db.agendas).get();
      expect(agendas.map((a) => a.visitaId).toSet(), {'vis-1', 'vis-2'});
      expect(agendas.map((a) => a.id).toSet().length, 2);
      expect(
        await db.select(db.houseStatuses).get(),
        isEmpty,
        reason: 'la agenda cumplida no pinta; la venta pinta en S9',
      );
    });

    test('la agenda cumplida sube después de la visita y con los datos de la visita', () async {
      final visita = visitaDe('vis-1', creada: t0.add(const Duration(minutes: 3)));

      await repo.registrarVisita(visita);

      final cola = encolador.encolados.map((c) => c.entidad).toList();
      expect(cola.indexOf('visita'), lessThan(cola.indexOf('agenda')));
      final agenda = encolador.encolados.firstWhere((c) => c.entidad == 'agenda').payload;
      expect(agenda['estado'], 'COMPLETADA');
      expect(agenda['visita_id'], 'vis-1');
      expect(agenda['espacio_persona_id'], visita.espacioPersonaId);
      expect(agenda['colportor_id'], visita.colportorId);
      expect(DateTime.parse(agenda['fecha_programada']! as String), visita.fecha);
    });
  });
}
