// QA de #538 (tanda 1, QA #404): la validación de `ubicacion_alt_id` y `jornada_id` antes de escribir
// y de encolar. Complementa los tests del implementador con lo que no cruzan: el rechazo no deja
// nada a medias (ni nota huérfana, ni agenda tocada, ni color de la casa movido), el reintento con los
// mismos ids sigue siendo idempotente aunque la fila referida se haya dado de baja entre medio, una
// jornada cerrada sigue valiendo, y dos toques seguidos no duplican. Todo contra la DB real en
// memoria.
import 'dart:convert';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/agenda_repository_impl.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
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
    );
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  Agenda conAlt(String id, String? alt, {TipoAgenda tipo = TipoAgenda.cobranza}) => Agenda(
    id: id,
    espacioId: 'esp-1',
    espacioPersonaId: 'ep-1',
    tipo: tipo,
    fechaProgramada: DateTime.utc(2026, 10, 25, 14),
    ubicacionAltId: alt,
    colportorId: 'col-1',
    auditoria: auditoriaDe(),
  );

  Future<List<String>> todo() async => [
    for (final f in await db.select(db.agendas).get()) 'agenda:${jsonEncode(f.toJson())}',
    for (final f in await db.select(db.visitas).get()) 'visita:${jsonEncode(f.toJson())}',
    for (final f in await db.select(db.notas).get()) 'nota:${jsonEncode(f.toJson())}',
    for (final f in await db.select(db.houseStatuses).get()) 'hs:${jsonEncode(f.toJson())}',
    for (final c in encolador.encolados) 'cola:${c.entidad}:${c.operacion.name}',
  ];

  group('ubicación alternativa de la agenda', () {
    test('una ubicación alternativa que nunca existió: rechazo, nada escrito ni encolado y ningún '
        'texto del rechazo lleva el id', () async {
      final antes = await todo();

      final r = await repo.agendar(
        conAlt('age-1', 'ub-fantasma'),
        nota: notaDe('not-1', texto: 'no debe quedar huérfana'),
      );

      final falla = r.fold((f) => f, (_) => fail('debía rechazarse')) as FailureValidacion;
      expect(falla.campos.keys, ['ubicacion']);
      expect(falla.mensaje, isNot(contains('ub-fantasma')));
      expect(falla.toString(), isNot(contains('ub-fantasma')));
      expect(await todo(), antes, reason: 'ni agenda, ni nota, ni color de la casa, ni cola');
    });

    test('sin ubicación alternativa (null) la agenda se guarda como siempre', () async {
      final r = await repo.agendar(conAlt('age-1', null));
      expect(r.isRight(), isTrue);
      expect(encolador.encolados.where((c) => c.entidad == 'agenda'), hasLength(1));
    });

    test('la ubicación alternativa dada de baja DESPUÉS de agendar no rompe el reintento con el '
        'mismo id: responde lo mismo que la primera vez y no escribe de nuevo', () async {
      await sembrarUbicacion(db, id: 'ub-alt');
      final primera = await repo.agendar(conAlt('age-1', 'ub-alt'));
      expect(primera.isRight(), isTrue);
      await (db.update(
        db.ubicaciones,
      )..where((u) => u.id.equals('ub-alt'))).write(UbicacionesCompanion(deletedAt: Value(t0)));
      final antes = await todo();

      final segunda = await repo.agendar(conAlt('age-1', 'ub-alt'));

      expect(segunda.isRight(), isTrue, reason: 'un reintento no pierde la agenda ya guardada');
      expect(await todo(), antes);
    });

    test('dos «Agendar» a la vez con la misma agenda y la ubicación alternativa rota: los dos '
        'se rechazan y no queda nada', () async {
      final rs = await Future.wait([
        repo.agendar(conAlt('age-1', 'ub-fantasma')),
        repo.agendar(conAlt('age-1', 'ub-fantasma')),
      ]);
      expect(rs.every((r) => r.isLeft()), isTrue);
      expect(await db.select(db.agendas).get(), isEmpty);
      expect(encolador.encolados, isEmpty);
    });

    test('dos «Agendar» a la vez con la ubicación alternativa viva: una sola fila y una sola '
        'operación en la cola', () async {
      await sembrarUbicacion(db, id: 'ub-alt');
      final rs = await Future.wait([
        repo.agendar(conAlt('age-1', 'ub-alt')),
        repo.agendar(conAlt('age-1', 'ub-alt')),
      ]);
      expect(rs.every((r) => r.isRight()), isTrue);
      expect(await db.select(db.agendas).get(), hasLength(1));
      expect(encolador.encolados.where((c) => c.entidad == 'agenda'), hasLength(1));
    });

    test(
      'la ubicación alternativa de OTRA casa viva sí vale: es una ubicación del teléfono',
      () async {
        await sembrarUbicacion(db, id: 'ub-otra', tipo: 'EDIFICIO');
        final r = await repo.agendar(conAlt('age-1', 'ub-otra'));
        expect(r.isRight(), isTrue);
      },
    );

    test(
      'un id de ubicación con comillas y SQL no se interpreta (consulta parametrizada)',
      () async {
        final r = await repo.agendar(conAlt('age-1', "x' OR '1'='1"));
        expect(r.isLeft(), isTrue);
        expect(await db.select(db.agendas).get(), isEmpty);
        expect(await db.select(db.ubicaciones).get(), hasLength(1));
      },
    );
  });

  group('jornada de la visita', () {
    test('una jornada ya cerrada (con hora de fin) sigue valiendo para la visita', () async {
      await sembrarJornada(db);
      await (db.update(db.jornadas)..where((j) => j.id.equals('jor-1'))).write(
        JornadasCompanion(fin: Value(t0.add(const Duration(hours: 5)))),
      );
      final r = await repo.registrarVisita(visitaDe('vis-1', jornadaId: 'jor-1'));
      expect(r.isRight(), isTrue);
    });

    test('sin jornada (null) la visita se guarda: la de hoy puede ir sin jornada (#607)', () async {
      final r = await repo.registrarVisita(visitaDe('vis-1'));
      expect(r.isRight(), isTrue);
      expect((await db.select(db.visitas).get()).single.jornadaId, isNull);
    });

    test('con la jornada dada de baja y una agenda por cumplir: la visita se rechaza, la agenda '
        'sigue PROGRAMADA y la nota no se escribe', () async {
      await sembrarJornada(db, borrada: t0);
      await repo.agendar(conAlt('age-1', null, tipo: TipoAgenda.entrevista));
      final antes = await todo();

      final r = await repo.registrarVisita(
        visitaDe('vis-1', jornadaId: 'jor-1'),
        agendaId: 'age-1',
        nota: notaDe('not-1', texto: 'tampoco debe quedar'),
      );

      expect(r.isLeft(), isTrue);
      expect(await todo(), antes);
      expect((await db.select(db.agendas).get()).single.estado, EstadoAgenda.programada.codigo);
    });

    test('el mensaje de la jornada dice qué pasó y qué hacer, sin el id', () async {
      final r = await repo.registrarVisita(visitaDe('vis-1', jornadaId: 'jor-secreta'));
      final falla = r.fold((f) => f, (_) => fail('debía rechazarse')) as FailureValidacion;
      expect(
        falla.mensaje,
        falla.campos['jornada'],
        reason: 'las pantallas que leen `mensaje` lo ven',
      );
      expect(falla.campos['jornada'], contains('Volvé al mapa'));
      expect(falla.campos['jornada'], isNot(contains('jor-secreta')));
      expect(falla.campos['jornada'], isNot(contains('registrala')));
      expect(falla.toString(), isNot(contains('jor-secreta')));
    });

    test('la jornada dada de baja DESPUÉS de registrar la visita no rompe el reintento con el '
        'mismo id', () async {
      await sembrarJornada(db);
      expect((await repo.registrarVisita(visitaDe('vis-1', jornadaId: 'jor-1'))).isRight(), isTrue);
      await (db.update(
        db.jornadas,
      )..where((j) => j.id.equals('jor-1'))).write(JornadasCompanion(deletedAt: Value(t0)));
      final antes = await todo();

      final otra = await repo.registrarVisita(visitaDe('vis-1', jornadaId: 'jor-1'));

      expect(otra.isRight(), isTrue, reason: 'el reintento no pierde la visita ya guardada');
      expect(await todo(), antes);
    });

    test(
      'dos «Registrar» a la vez con la jornada viva: una sola visita y una sola operación',
      () async {
        await sembrarJornada(db);
        final rs = await Future.wait([
          repo.registrarVisita(visitaDe('vis-1', jornadaId: 'jor-1')),
          repo.registrarVisita(visitaDe('vis-1', jornadaId: 'jor-1')),
        ]);
        expect(rs.every((r) => r.isRight()), isTrue);
        expect(await db.select(db.visitas).get(), hasLength(1));
        expect(encolador.encolados.where((c) => c.entidad == 'visita'), hasLength(1));
      },
    );
  });
}
