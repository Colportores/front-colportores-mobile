// La agenda y las visitas (BACK-HU-VIS-001) contra las tablas reales: AppDatabase en memoria, mismo
// esquema y mismos CHECK que en el dispositivo, con el servicio real de `house_status`.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/motivo_rechazo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita_guardada.dart';
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
  late AgendaLocalDataSourceDrift local;
  final t1 = t0.add(const Duration(minutes: 10));
  final t2 = t0.add(const Duration(minutes: 20));

  AgendaLocalDataSourceDrift armar(HouseStatusUpdaterDrift updater) {
    var n = 0;
    return AgendaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: updater,
      generarId: () => 'age-esp-${++n}',
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = armar(HouseStatusUpdaterDrift(db, encolador: encolador));
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  Future<List<AgendaFila>> agendas() => db.select(db.agendas).get();
  Future<List<VisitaFila>> visitas() => db.select(db.visitas).get();
  Future<List<HouseStatusFila>> casas() => db.select(db.houseStatuses).get();
  Future<List<NotaFila>> notas() => db.select(db.notas).get();
  List<String> cola() => [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];

  Matcher rechazaCon(MotivoRechazoAgenda motivo) =>
      throwsA(isA<AgendaRechazadaException>().having((e) => e.motivo, 'motivo', motivo));

  group('agendar', () {
    test('guarda la agenda, la encola entera y deja la casa en «entrevista programada»', () async {
      final r = await local.agendar(agendaDe('age-1', slot: 'mid_morning', esEstricta: true));

      expect(r.yaEstaba, isFalse);
      expect(r.agenda.id, 'age-1');
      final fila = (await agendas()).single;
      expect(
        [fila.tipo, fila.estado, fila.esEstricta, fila.slotCodigo],
        ['ENTREVISTA', 'PROGRAMADA', true, 'mid_morning'],
      );
      expect(fila.fechaProgramada, DateTime.utc(2026, 10, 25, 14));
      expect(cola(), ['agenda:insert', 'house_status:insert']);
      final payload = encolador.encolados.first.payload;
      expect(payload['id'], 'age-1');
      expect(payload['espacio_persona_id'], 'ep-1');
      expect(payload['tipo'], 'ENTREVISTA');
      expect(payload['estado'], 'PROGRAMADA');
      expect(payload['es_estricta'], true);
      expect(payload['fecha_programada'], '2026-10-25T14:00:00.000Z');
      expect((await casas()).single.color, 'ENTREVISTA_PROGRAMADA');
    });

    test('con una nota: la guarda como fila de nota (AGENDA) y no la manda al sync', () async {
      await local.agendar(agendaDe('age-1'), nota: notaDe('nota-1', texto: 'el perro es bravo'));

      final nota = (await notas()).single;
      expect(
        [nota.targetType, nota.targetId, nota.texto],
        ['AGENDA', 'age-1', 'el perro es bravo'],
      );
      expect(cola(), ['agenda:insert', 'house_status:insert']);
      for (final cambio in encolador.encolados) {
        expect('${cambio.payload}', isNot(contains('perro')));
      }
    });

    test('una agenda de cobranza se guarda y se encola, pero no pinta la casa', () async {
      await local.agendar(agendaDe('age-1', tipo: TipoAgenda.cobranza));

      expect(cola(), ['agenda:insert']);
      expect(await casas(), isEmpty);
    });

    test('con el mismo id otra vez (doble tap): no escribe ni encola nada de nuevo', () async {
      await local.agendar(agendaDe('age-1'), nota: notaDe('nota-1'));
      encolador.encolados.clear();

      final r = await local.agendar(agendaDe('age-1'), nota: notaDe('nota-1'));

      expect(r.yaEstaba, isTrue);
      expect(await agendas(), hasLength(1));
      expect(await notas(), hasLength(1));
      expect(encolador.encolados, isEmpty);
    });

    test('dos veces a la vez (doble envío): se serializan y queda una sola agenda', () async {
      final resultados = await Future.wait([
        local.agendar(agendaDe('age-1')),
        local.agendar(agendaDe('age-1')),
      ]);

      expect(resultados.map((r) => r.yaEstaba), unorderedEquals([false, true]));
      expect(await agendas(), hasLength(1));
      expect(cola(), ['agenda:insert', 'house_status:insert']);
    });

    test('para un vínculo que no está en el teléfono: la rechaza y no deja nada', () async {
      await expectLater(
        local.agendar(agendaDe('age-1', vinculo: 'ep-no-existe'), nota: notaDe('nota-1')),
        rechazaCon(MotivoRechazoAgenda.personaInexistente),
      );

      expect(await agendas(), isEmpty);
      expect(await notas(), isEmpty);
      expect(encolador.encolados, isEmpty);
    });

    test('para un vínculo dado de baja: la rechaza', () async {
      await db.delete(db.espacioPersonas).go();
      await sembrarVinculo(db, borrado: t1);

      await expectLater(
        local.agendar(agendaDe('age-1')),
        rechazaCon(MotivoRechazoAgenda.personaInexistente),
      );
    });

    test('si falla el encolado de la agenda: no queda ni la agenda ni la nota', () async {
      encolador.fallarCon = StateError('motor apagado');

      await expectLater(local.agendar(agendaDe('age-1'), nota: notaDe('nota-1')), throwsStateError);

      expect(await agendas(), isEmpty);
      expect(await notas(), isEmpty);
      expect(await casas(), isEmpty);
    });

    test(
      'si falla el encolado del color de la casa: se revierte también la agenda ya encolada',
      () async {
        encolador
          ..fallarCon = StateError('motor apagado')
          ..fallarDespuesDe = 1;

        await expectLater(local.agendar(agendaDe('age-1')), throwsStateError);

        expect(await agendas(), isEmpty);
        expect(await casas(), isEmpty);
      },
    );

    test('tras una falla, el mismo envío se puede reintentar y sale bien', () async {
      encolador.fallarCon = StateError('motor apagado');
      await expectLater(local.agendar(agendaDe('age-1')), throwsStateError);
      encolador.fallarCon = null;
      encolador.encolados.clear();

      final r = await local.agendar(agendaDe('age-1'));

      expect(r.yaEstaba, isFalse);
      expect(cola(), ['agenda:insert', 'house_status:insert']);
    });

    test(
      'le pide el recálculo a la ubicación del vínculo, con el instante y la colportora',
      () async {
        final espia = HouseStatusUpdaterEspia();
        final conEspia = AgendaLocalDataSourceDrift(
          db,
          encolador: encolador,
          estadoDeLasCasas: espia,
        );

        await conEspia.agendar(agendaDe('age-1', creada: t1));

        expect(espia.llamadas.single, (ubicacionId: 'ub-1', ahora: t1, colportorId: 'col-1'));
      },
    );

    test('con un espacio que no está en el teléfono: la rechaza y no encola nada', () async {
      await expectLater(
        local.agendar(agendaDe('age-1', espacio: 'esp-que-no-llego', vinculo: null)),
        rechazaCon(MotivoRechazoAgenda.espacioInexistente),
      );

      expect(await agendas(), isEmpty);
      expect(cola(), isEmpty);
    });

    test('con una persona de otra casa: la rechaza (no se cuela en este espacio)', () async {
      await sembrarEspacio(db, id: 'esp-2', numeroDepto: '2B');
      await sembrarVinculo(db, id: 'ep-2', espacioId: 'esp-2', personaId: 'per-2');

      await expectLater(
        local.agendar(agendaDe('age-1', espacio: 'esp-1', vinculo: 'ep-2')),
        rechazaCon(MotivoRechazoAgenda.personaInexistente),
      );
      expect(await agendas(), isEmpty);
    });

    test('sin persona: la agenda se guarda con el espacio y sin vínculo', () async {
      await local.agendar(agendaDe('age-1', vinculo: null));

      final fila = (await agendas()).single;
      expect([fila.espacioId, fila.espacioPersonaId], ['esp-1', null]);
      final subida = encolador.encolados.firstWhere((c) => c.entidad == 'agenda');
      expect(subida.payload['espacio_persona_id'], isNull);
      expect(subida.payload['espacio_id'], 'esp-1');
    });

    test('en una casa dada de baja: guarda la agenda igual, sin tocar el color', () async {
      await db.update(db.ubicaciones).write(UbicacionesCompanion(deletedAt: Value(t1)));

      await local.agendar(agendaDe('age-1'));

      expect(await agendas(), hasLength(1));
      expect(await casas(), isEmpty);
    });
  });

  group('cancelar', () {
    setUp(() async {
      await local.agendar(agendaDe('age-1'));
      encolador.encolados.clear();
    });

    test(
      'pasa la agenda a CANCELADA, la encola con su versión y la casa vuelve a «Sin visita»',
      () async {
        final r = await local.cancelar('age-1', ahora: t1);

        expect(r.escribio, isTrue);
        expect(r.agenda.estado, EstadoAgenda.cancelada);
        expect((await agendas()).single.estado, 'CANCELADA');
        expect((await agendas()).single.updatedAt, t1);
        expect(cola(), ['agenda:update', 'house_status:delete']);
        expect(encolador.encolados.first.payload['estado'], 'CANCELADA');
        expect((await casas()).single.deletedAt, t1);
      },
    );

    test('con un rechazo anterior en la casa: vuelve al rojo', () async {
      await insertarVisita(db, visitaDe('vis-0', resultado: TipoResultadoVisita.rechazo));

      await local.cancelar('age-1', ahora: t1);

      expect((await casas()).single.color, 'RECHAZO');
      expect((await casas()).single.deletedAt, isNull);
    });

    test('dos veces (doble tap): la segunda no escribe ni encola', () async {
      await local.cancelar('age-1', ahora: t1);
      encolador.encolados.clear();

      final r = await local.cancelar('age-1', ahora: t2);

      expect(r.escribio, isFalse);
      expect(r.agenda.estado, EstadoAgenda.cancelada);
      expect((await agendas()).single.updatedAt, t1);
      expect(encolador.encolados, isEmpty);
    });

    test('una agenda ya cumplida: no se puede cancelar', () async {
      await local.registrarVisita(visitaDe('vis-1', creada: t1), agendaId: 'age-1');

      await expectLater(
        local.cancelar('age-1', ahora: t2),
        rechazaCon(MotivoRechazoAgenda.agendaCerrada),
      );
      expect((await agendas()).single.estado, 'CUMPLIDA');
    });

    test('una agenda que no existe o está dada de baja: la rechaza', () async {
      await expectLater(
        local.cancelar('age-fantasma', ahora: t1),
        rechazaCon(MotivoRechazoAgenda.agendaInexistente),
      );
      await db.update(db.agendas).write(AgendasCompanion(deletedAt: Value(t1)));
      await expectLater(
        local.cancelar('age-1', ahora: t1),
        rechazaCon(MotivoRechazoAgenda.agendaInexistente),
      );
    });

    test('si falla el encolado: la agenda sigue pendiente y se puede reintentar', () async {
      encolador.fallarCon = StateError('motor apagado');

      await expectLater(local.cancelar('age-1', ahora: t1), throwsStateError);

      expect((await agendas()).single.estado, 'PROGRAMADA');
      expect((await casas()).single.deletedAt, isNull);
      encolador.fallarCon = null;
      expect((await local.cancelar('age-1', ahora: t1)).escribio, isTrue);
    });
  });

  group('registrarVisita', () {
    test(
      'sin agenda: guarda la visita, la encola entera y pinta la casa según el resultado',
      () async {
        final r = await local.registrarVisita(
          visitaDe('vis-1', resultado: TipoResultadoVisita.noContesto, jornadaId: 'jor-1'),
        );

        expect(r.yaEstaba, isFalse);
        final fila = (await visitas()).single;
        expect([fila.tipoResultado, fila.jornadaId], ['NO_CONTESTO', 'jor-1']);
        expect(cola(), ['visita:insert', 'agenda:insert', 'house_status:insert']);
        final payload = encolador.encolados.first.payload;
        expect(payload['tipo_resultado'], 'NO_CONTESTO');
        expect(payload['jornada_id'], 'jor-1');
        expect((await casas()).single.color, 'SIN_CONTESTAR');
      },
    );

    test('NO_CONTESTO con la agenda de la casa: guarda la visita y marca la agenda NO_CUMPLIDA '
        '(apunta a la visita), sin crear una agenda cumplida de más', () async {
      await local.agendar(agendaDe('age-1'));
      encolador.encolados.clear();

      final r = await local.registrarVisita(
        visitaDe('vis-1', resultado: TipoResultadoVisita.noContesto, creada: t1),
        agendaId: 'age-1',
      );

      expect([r.yaEstaba, r.agendaNoCumplida, r.agendaIgnorada], [false, true, null]);
      expect([r.agendaAfectadaId, r.agendaCreadaId], ['age-1', null]);
      expect((await visitas()).single.tipoResultado, 'NO_CONTESTO');
      final agenda = (await agendas()).single;
      expect([agenda.estado, agenda.visitaId], ['NO_CUMPLIDA', 'vis-1']);
      expect(cola(), ['visita:insert', 'agenda:update', 'house_status:update']);
      // Ya no espera la visita: la casa se pinta de «sin contestar» (6), no de entrevista programada.
      expect((await casas()).single.color, 'SIN_CONTESTAR');
    });

    test('NO_CONTESTO con una agenda cerrada: sigue siendo espontanea, con su agenda cumplida y el '
        'motivo', () async {
      await local.agendar(agendaDe('age-1'));
      await local.cancelar('age-1', ahora: t1);

      final r = await local.registrarVisita(
        visitaDe('vis-1', resultado: TipoResultadoVisita.noContesto, creada: t2),
        agendaId: 'age-1',
      );

      expect([r.agendaNoCumplida, r.agendaIgnorada], [false, MotivoAgendaIgnorada.cerrada]);
      expect((await agendas()).map((a) => a.estado), ['CANCELADA', 'CUMPLIDA']);
    });

    test('RECHAZO con la agenda de la casa: la cumple (lectura de la HU a confirmar)', () async {
      await local.agendar(agendaDe('age-1'));

      final r = await local.registrarVisita(
        visitaDe('vis-1', resultado: TipoResultadoVisita.rechazo, creada: t1),
        agendaId: 'age-1',
      );

      expect(r.agendaNoCumplida, isFalse);
      expect((await agendas()).single.estado, 'CUMPLIDA');
      expect((await casas()).single.color, 'RECHAZO');
    });

    test('con la agenda que cumple: la agenda pasa a CUMPLIDA apuntando a la visita, y se '
        'encola primero la visita', () async {
      await local.agendar(agendaDe('age-1'));
      encolador.encolados.clear();

      await local.registrarVisita(visitaDe('vis-1', creada: t1), agendaId: 'age-1');

      final agenda = (await agendas()).single;
      expect([agenda.estado, agenda.visitaId, agenda.updatedAt], ['CUMPLIDA', 'vis-1', t1]);
      expect(cola(), ['visita:insert', 'agenda:update', 'house_status:update']);
      expect(encolador.encolados[1].payload['visita_id'], 'vis-1');
      expect((await casas()).single.color, 'ENTREVISTA_SIN_VENTA');
    });

    test('sin agenda (visita espontánea): crea en la misma transacción la agenda CUMPLIDA de la '
        'visita y la encola después de ella', () async {
      final visita = visitaDe('vis-1', creada: t1);

      await local.registrarVisita(visita);

      final agenda = (await agendas()).single;
      expect(agenda.id, 'age-esp-1');
      expect(agenda.estado, 'CUMPLIDA');
      expect(agenda.tipo, 'ENTREVISTA');
      expect(agenda.visitaId, 'vis-1');
      expect(agenda.espacioPersonaId, visita.espacioPersonaId);
      expect(agenda.colportorId, visita.colportorId);
      expect(agenda.fechaProgramada, visita.fecha);
      expect([agenda.slotCodigo, agenda.esEstricta, agenda.deletedAt], [null, false, null]);
      expect(encolador.encolados[1].entidad, 'agenda');
      expect(encolador.encolados[1].payload['visita_id'], 'vis-1');
      expect(encolador.encolados[1].payload['estado'], 'CUMPLIDA');
    });

    test('la agenda de la espontánea no pinta la casa: solo cuenta el resultado', () async {
      await local.registrarVisita(visitaDe('vis-1', creada: t1));

      expect((await casas()).single.color, 'ENTREVISTA_SIN_VENTA');
    });

    test('con una nota: la guarda como fila de nota (VISITA) y no la manda al sync', () async {
      await local.registrarVisita(
        visitaDe('vis-1'),
        nota: notaDe('nota-1', texto: 'la hija está enferma'),
      );

      final nota = (await notas()).single;
      expect([nota.targetType, nota.targetId], ['VISITA', 'vis-1']);
      for (final cambio in encolador.encolados) {
        expect('${cambio.payload}', isNot(contains('enferma')));
      }
    });

    test(
      'con el mismo id otra vez (doble envío): no escribe ni encola de nuevo y no cierra otra agenda',
      () async {
        await local.agendar(agendaDe('age-1'));
        await local.agendar(agendaDe('age-2'));
        await local.registrarVisita(visitaDe('vis-1', creada: t1), agendaId: 'age-1');
        encolador.encolados.clear();

        final r = await local.registrarVisita(visitaDe('vis-1', creada: t1), agendaId: 'age-2');

        expect(r.yaEstaba, isTrue);
        expect(await visitas(), hasLength(1));
        expect(encolador.encolados, isEmpty);
        expect(
          (await db.select(db.agendas).get()).where((a) => a.estado == 'PROGRAMADA'),
          hasLength(1),
        );
      },
    );

    test('dos veces a la vez: se serializan y queda una sola visita', () async {
      final resultados = await Future.wait([
        local.registrarVisita(visitaDe('vis-1')),
        local.registrarVisita(visitaDe('vis-1')),
      ]);

      expect(resultados.map((r) => r.yaEstaba), unorderedEquals([false, true]));
      expect(await visitas(), hasLength(1));
    });

    test('para un vínculo que no está en el teléfono: la rechaza y no deja nada', () async {
      await expectLater(
        local.registrarVisita(visitaDe('vis-1', vinculo: 'ep-no-existe'), nota: notaDe('nota-1')),
        rechazaCon(MotivoRechazoAgenda.personaInexistente),
      );

      expect(await visitas(), isEmpty);
      expect(await notas(), isEmpty);
      expect(encolador.encolados, isEmpty);
    });

    test('con una agenda que no existe: guarda la visita igual, sin agenda, y avisa', () async {
      final r = await local.registrarVisita(visitaDe('vis-1'), agendaId: 'age-fantasma');

      expect(r.yaEstaba, isFalse);
      expect(r.agendaIgnorada, MotivoAgendaIgnorada.inexistente);
      expect((await visitas()).single.id, 'vis-1');
      expect(cola(), ['visita:insert', 'agenda:insert', 'house_status:insert']);
      expect((await agendas()).single.estado, 'CUMPLIDA');
    });

    test(
      'con una agenda de otra persona: guarda la visita igual y la agenda sigue pendiente',
      () async {
        await sembrarVinculo(db, id: 'ep-2', espacioId: 'esp-1', personaId: 'per-2');
        await local.agendar(agendaDe('age-1', vinculo: 'ep-2'));
        encolador.encolados.clear();

        final r = await local.registrarVisita(visitaDe('vis-1'), agendaId: 'age-1');

        expect(r.agendaIgnorada, MotivoAgendaIgnorada.deOtraPersona);
        expect((await visitas()).single.id, 'vis-1');
        final ajena = (await agendas()).singleWhere((a) => a.id == 'age-1');
        expect([ajena.estado, ajena.visitaId], ['PROGRAMADA', null]);
        expect(cola().where((c) => c == 'agenda:update'), isEmpty, reason: 'no la tocó');
        expect((await agendas()).singleWhere((a) => a.id != 'age-1').visitaId, 'vis-1');
      },
    );

    test(
      'con una agenda ya cumplida o cancelada: guarda la visita igual, no toca la agenda y avisa',
      () async {
        await local.agendar(agendaDe('age-1'));
        await local.agendar(agendaDe('age-2'));
        await local.cancelar('age-2', ahora: t1);
        await local.registrarVisita(visitaDe('vis-0', creada: t1), agendaId: 'age-1');
        Future<List<AgendaFila>> originales() async =>
            (await agendas()).where((a) => a.id == 'age-1' || a.id == 'age-2').toList();
        final antes = await originales();

        for (final agendaId in ['age-1', 'age-2']) {
          final r = await local.registrarVisita(
            visitaDe('vis-$agendaId', creada: t2),
            agendaId: agendaId,
          );
          expect(r.agendaIgnorada, MotivoAgendaIgnorada.cerrada, reason: agendaId);
          expect(r.agendaIgnorada!.aviso, contains('guardamos la visita igual'));
        }

        expect(await visitas(), hasLength(3));
        expect(await originales(), antes, reason: 'las agendas cerradas quedan como estaban');
        expect(
          (await agendas()).where((a) => a.id.startsWith('age-esp')).map((a) => a.visitaId),
          unorderedEquals(['vis-age-1', 'vis-age-2']),
          reason: 'cada visita nace con su agenda CUMPLIDA',
        );
      },
    );

    test('con la agenda que sirve: no hay aviso', () async {
      await local.agendar(agendaDe('age-1'));

      final r = await local.registrarVisita(visitaDe('vis-1', creada: t1), agendaId: 'age-1');

      expect(r.agendaIgnorada, isNull);
    });

    test(
      'si falla el encolado a mitad: la visita no queda, la agenda sigue pendiente y se puede reintentar',
      () async {
        await local.agendar(agendaDe('age-1'));
        encolador.encolados.clear();
        encolador
          ..fallarCon = StateError('motor apagado')
          ..fallarDespuesDe = 1;

        await expectLater(
          local.registrarVisita(
            visitaDe('vis-1', creada: t1),
            agendaId: 'age-1',
            nota: notaDe('nota-1'),
          ),
          throwsStateError,
        );

        expect(await visitas(), isEmpty);
        expect(await notas(), isEmpty);
        expect((await agendas()).single.estado, 'PROGRAMADA');
        expect((await agendas()).single.visitaId, isNull);
        expect((await casas()).single.color, 'ENTREVISTA_PROGRAMADA');

        encolador
          ..fallarCon = null
          ..encolados.clear();
        final r = await local.registrarVisita(visitaDe('vis-1', creada: t1), agendaId: 'age-1');
        expect(r.yaEstaba, isFalse);
        expect((await agendas()).single.estado, 'CUMPLIDA');
      },
    );

    test('si falla el recálculo del color: la visita y la agenda quedan como estaban', () async {
      await local.agendar(agendaDe('age-1'));
      final falla = AgendaLocalDataSourceDrift(
        db,
        encolador: encolador,
        estadoDeLasCasas: HouseStatusUpdaterEspia()..fallarCon = StateError('sin cálculo'),
      );

      await expectLater(
        falla.registrarVisita(visitaDe('vis-1', creada: t1), agendaId: 'age-1'),
        throwsStateError,
      );

      expect(await visitas(), isEmpty);
      expect((await agendas()).single.estado, 'PROGRAMADA');
    });
  });

  group('dos acciones seguidas, sin esperar a la primera', () {
    test(
      'agendar y registrar la visita que la cumple: las dos salen bien y en ese orden',
      () async {
        final agendada = local.agendar(agendaDe('age-1'));
        final visitada = local.registrarVisita(visitaDe('vis-1', creada: t1), agendaId: 'age-1');

        await Future.wait([agendada, visitada]);

        expect((await agendas()).single.estado, 'CUMPLIDA');
        expect(cola().where((c) => c.startsWith('house_status')), isNotEmpty);
        expect((await casas()).single.color, 'ENTREVISTA_SIN_VENTA');
      },
    );

    test('agendar y cancelar de inmediato: la casa queda sin color', () async {
      final agendada = local.agendar(agendaDe('age-1'));
      final cancelada = local.cancelar('age-1', ahora: t1);

      await Future.wait([agendada, cancelada]);

      expect((await agendas()).single.estado, 'CANCELADA');
      expect((await casas()).single.deletedAt, isNotNull);
    });

    test('cancelar y registrar la visita de la misma agenda a la vez: la visita no se pierde y '
        'la agenda queda cancelada', () async {
      await local.agendar(agendaDe('age-1'));
      encolador.encolados.clear();

      final cancelada = local.cancelar('age-1', ahora: t1);
      final visitada = local.registrarVisita(visitaDe('vis-1', creada: t2), agendaId: 'age-1');
      await cancelada;
      final resultado = await visitada;

      expect(resultado.agendaIgnorada, MotivoAgendaIgnorada.cerrada);
      expect((await agendas()).singleWhere((a) => a.id == 'age-1').estado, 'CANCELADA');
      expect((await visitas()).single.id, 'vis-1');
    });
  });

  group('un edificio con dos deptos', () {
    setUp(() async {
      await db.close();
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      encolador = EncoladorSyncEnMemoria();
      local = armar(HouseStatusUpdaterDrift(db, encolador: encolador));
      await sembrarEdificio(db);
    });

    test(
      'una agenda en un depto manda sobre un rechazo en el otro, y al cancelarla gana el rechazo',
      () async {
        await local.agendar(agendaDe('age-1'));
        await local.registrarVisita(
          visitaDe(
            'vis-1',
            espacio: 'esp-2',
            vinculo: 'ep-2',
            resultado: TipoResultadoVisita.rechazo,
            creada: t1,
          ),
        );
        expect((await casas()).single.color, 'ENTREVISTA_PROGRAMADA');

        await local.cancelar('age-1', ahora: t2);

        expect((await casas()).single.color, 'RECHAZO');
        expect(await casas(), hasLength(1), reason: 'una fila por ubicación');
      },
    );
  });

  group('deshacerVisita (el «Deshacer» de «Guardado»)', () {
    test(
      'una visita espontánea: se da de baja con la agenda que creó y sus notas, y la casa vuelve '
      'a «Sin visita»',
      () async {
        final r = await local.registrarVisita(
          visitaDe('vis-1', resultado: TipoResultadoVisita.rechazo, creada: t1),
          nota: notaDe('nota-1'),
        );
        expect(r.agendaCreadaId, isNotNull);
        expect((await casas()).single.color, 'RECHAZO');
        encolador.encolados.clear();

        final d = await local.deshacerVisita('vis-1', agendaCreadaId: r.agendaCreadaId, ahora: t2);

        expect(d.escribio, isTrue);
        expect((await visitas()).single.deletedAt, isNotNull);
        expect((await agendas()).single.deletedAt, isNotNull);
        expect((await notas()).single.deletedAt, isNotNull);
        final casa = await casas();
        expect(casa.isEmpty || casa.single.deletedAt != null, isTrue, reason: 'sin color');
        expect(cola(), containsAll(['visita:delete', 'agenda:delete']));
        expect(cola().where((c) => c == 'visita:delete'), hasLength(1));
      },
    );

    test(
      'una visita que cumplió la agenda de la casa: la agenda vuelve a «Programada» sin visita y '
      'la casa a su color',
      () async {
        await local.agendar(agendaDe('age-1'));
        final r = await local.registrarVisita(visitaDe('vis-1', creada: t1), agendaId: 'age-1');
        expect(r.agendaAfectadaId, 'age-1');
        expect((await agendas()).single.estado, 'CUMPLIDA');
        encolador.encolados.clear();

        await local.deshacerVisita('vis-1', agendaAfectadaId: r.agendaAfectadaId, ahora: t2);

        final agenda = (await agendas()).single;
        expect([agenda.estado, agenda.visitaId, agenda.deletedAt], ['PROGRAMADA', null, null]);
        expect((await visitas()).single.deletedAt, isNotNull);
        expect((await casas()).single.color, 'ENTREVISTA_PROGRAMADA');
        expect(cola(), containsAll(['visita:delete', 'agenda:update']));
      },
    );

    test(
      'un reintento con los mismos ids sobre una visita que cumplió la cita: sigue diciendo que la '
      'cumplió (no que la creó) y «Deshacer» la vuelve a «Programada», sin darla de baja',
      () async {
        await local.agendar(agendaDe('age-1'));
        await local.registrarVisita(visitaDe('vis-1', creada: t1), agendaId: 'age-1');

        // El reintento ya no encuentra la cita programada: llega sin agendaId.
        final r = await local.registrarVisita(visitaDe('vis-1', creada: t1));

        expect(r.yaEstaba, isTrue);
        expect([r.agendaAfectadaId, r.agendaCreadaId], ['age-1', null]);
        encolador.encolados.clear();

        await local.deshacerVisita(
          'vis-1',
          agendaCreadaId: r.agendaCreadaId,
          agendaAfectadaId: r.agendaAfectadaId,
          ahora: t2,
        );

        final agenda = (await agendas()).single;
        expect([agenda.estado, agenda.visitaId, agenda.deletedAt], ['PROGRAMADA', null, null]);
        expect(cola(), containsAll(['visita:delete', 'agenda:update']));
        expect(cola(), isNot(contains('agenda:delete')));
      },
    );

    test('un reintento con los mismos ids sobre una visita espontánea: sigue diciendo que creó su '
        'agenda y «Deshacer» la da de baja', () async {
      final primera = await local.registrarVisita(visitaDe('vis-1', creada: t1));
      final r = await local.registrarVisita(visitaDe('vis-1', creada: t1));

      expect(r.yaEstaba, isTrue);
      expect([r.agendaCreadaId, r.agendaAfectadaId], [primera.agendaCreadaId, null]);
    });

    test('un «No contestó» sobre la agenda de la casa: al deshacer, la agenda vuelve a '
        '«Programada»', () async {
      await local.agendar(agendaDe('age-1'));
      final r = await local.registrarVisita(
        visitaDe('vis-1', resultado: TipoResultadoVisita.noContesto, creada: t1),
        agendaId: 'age-1',
      );
      expect([r.agendaNoCumplida, r.agendaAfectadaId], [true, 'age-1']);
      expect((await agendas()).single.estado, 'NO_CUMPLIDA');

      await local.deshacerVisita('vis-1', agendaAfectadaId: r.agendaAfectadaId, ahora: t2);

      final agenda = (await agendas()).single;
      expect([agenda.estado, agenda.visitaId], ['PROGRAMADA', null]);
      expect((await casas()).single.color, 'ENTREVISTA_PROGRAMADA');
    });

    test('dos veces (doble toque): la segunda no escribe ni encola', () async {
      final r = await local.registrarVisita(visitaDe('vis-1', creada: t1));
      await local.deshacerVisita('vis-1', agendaCreadaId: r.agendaCreadaId, ahora: t2);
      encolador.encolados.clear();

      final otra = await local.deshacerVisita(
        'vis-1',
        agendaCreadaId: r.agendaCreadaId,
        ahora: t2.add(const Duration(minutes: 1)),
      );

      expect(otra.escribio, isFalse);
      expect(cola(), isEmpty);
    });

    test('una visita que no está en el teléfono: la rechaza', () async {
      await expectLater(
        local.deshacerVisita('vis-que-no-esta', ahora: t2),
        rechazaCon(MotivoRechazoAgenda.visitaInexistente),
      );
    });

    test(
      'con la agenda de otra visita: no la toca (solo se suelta lo que la visita tocó)',
      () async {
        await local.agendar(agendaDe('age-1'));
        await local.registrarVisita(visitaDe('vis-1', creada: t1), agendaId: 'age-1');
        await local.registrarVisita(visitaDe('vis-2', creada: t2));

        await local.deshacerVisita('vis-2', agendaAfectadaId: 'age-1', ahora: t2);

        final propia = (await agendas()).singleWhere((a) => a.id == 'age-1');
        expect([propia.estado, propia.visitaId], ['CUMPLIDA', 'vis-1']);
      },
    );

    test('si falla el encolado a mitad: no queda nada a medias y se puede reintentar', () async {
      await local.agendar(agendaDe('age-1'));
      final r = await local.registrarVisita(visitaDe('vis-1', creada: t1), agendaId: 'age-1');
      encolador.encolados.clear();
      encolador
        ..fallarCon = StateError('motor apagado')
        ..fallarDespuesDe = 1;

      await expectLater(
        local.deshacerVisita('vis-1', agendaAfectadaId: r.agendaAfectadaId, ahora: t2),
        throwsStateError,
      );

      expect((await visitas()).single.deletedAt, isNull);
      expect((await agendas()).single.estado, 'CUMPLIDA');

      encolador.fallarCon = null;
      final bien = await local.deshacerVisita(
        'vis-1',
        agendaAfectadaId: r.agendaAfectadaId,
        ahora: t2,
      );

      expect(bien.escribio, isTrue);
      expect((await agendas()).single.estado, 'PROGRAMADA');
    });
  });

  group('agendaProgramadaDe (la agenda que una visita viene a cumplir)', () {
    test('sin agendas: null', () async {
      expect(await local.agendaProgramadaDe('esp-1'), isNull);
    });

    test('una entrevista programada en la casa: la devuelve', () async {
      await local.agendar(agendaDe('age-1'));

      expect((await local.agendaProgramadaDe('esp-1'))!.id, 'age-1');
    });

    test('no devuelve las cumplidas, las canceladas, las dadas de baja, las de cobranza ni las de '
        'otro depto', () async {
      await sembrarEspacio(db, id: 'esp-2', numeroDepto: '2B');
      await local.agendar(agendaDe('cumplida'));
      await local.registrarVisita(visitaDe('vis-1', creada: t1), agendaId: 'cumplida');
      await local.agendar(agendaDe('cancelada'));
      await local.cancelar('cancelada', ahora: t1);
      await local.agendar(agendaDe('cobranza', tipo: TipoAgenda.cobranza));
      await local.agendar(agendaDe('otro-depto', espacio: 'esp-2', vinculo: null));

      expect(await local.agendaProgramadaDe('esp-1'), isNull);
      expect((await local.agendaProgramadaDe('esp-2'))!.id, 'otro-depto');
    });
  });

  group('leer', () {
    test('devuelve la agenda y la visita guardadas, o null si no están', () async {
      expect(await local.obtenerAgenda('age-1'), isNull);
      expect(await local.obtenerVisita('vis-1'), isNull);

      await local.agendar(agendaDe('age-1'));
      await local.registrarVisita(visitaDe('vis-1', creada: t1), agendaId: 'age-1');

      expect((await local.obtenerAgenda('age-1'))!.estado, EstadoAgenda.cumplida);
      expect((await local.obtenerAgenda('age-1'))!.visitaId, 'vis-1');
      expect((await local.obtenerVisita('vis-1'))!.tipoResultado, TipoResultadoVisita.entrevista);
    });
  });

  group('las tablas copian los CHECK del servidor', () {
    test('un tipo, un estado o un resultado que el servidor no admite no entra', () async {
      await expectLater(
        db.customInsert(
          'INSERT INTO agenda (id, espacio_persona_id, tipo, fecha_programada, estado, colportor_id, '
          'created_at, updated_at, es_estricta, sync_version) '
          "VALUES ('a', 'ep-1', 'VENTA', 0, 'PROGRAMADA', 'c', 0, 0, 0, 0)",
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customInsert(
          'INSERT INTO agenda (id, espacio_persona_id, tipo, fecha_programada, estado, colportor_id, '
          'created_at, updated_at, es_estricta, sync_version) '
          "VALUES ('a', 'ep-1', 'ENTREVISTA', 0, 'NO_CUMPLIDA', 'c', 0, 0, 0, 0)",
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customInsert(
          'INSERT INTO visita (id, espacio_persona_id, fecha, tipo_resultado, colportor_id, '
          'created_at, updated_at, sync_version) '
          "VALUES ('v', 'ep-1', 0, 'COBRANZA', 'c', 0, 0, 0)",
        ),
        throwsA(anything),
      );
    });
  });
}
