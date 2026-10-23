// QA de HU-VIS-005 (#410, PR #459): registrar el resultado de una visita, sin pantalla. Complementa
// los tests del implementador con la matriz resultado × (con/sin agenda), los avisos, los reintentos
// y dobles toques, los datos límite (espacios, emoji, textos pegados muy largos) y la privacidad
// (logs, `toString`, cola de sync). Corre contra la DB real en memoria.
import 'dart:convert';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/agenda_repository_impl.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita_guardada.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/registrar_resultado_visita_use_case.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';

typedef _R = TipoResultadoVisita;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late AgendaRepositoryImpl repositorio;
  late RegistrarResultadoVisitaUseCase casoDeUso;
  late MemoryOutput salidaDeLogs;
  var ids = 0;
  var reloj = t0;

  setUp(() async {
    ids = 0;
    reloj = t0.add(const Duration(minutes: 5));
    db = AppDatabase(
      NativeDatabase.memory(),
      logger: AppLogger(logger: Logger(level: Level.off)),
    );
    encolador = EncoladorSyncEnMemoria();
    salidaDeLogs = MemoryOutput();
    var espontaneas = 0;
    repositorio = AgendaRepositoryImpl(
      AgendaLocalDataSourceDrift(
        db,
        encolador: encolador,
        estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
        generarId: () => 'age-esp-${++espontaneas}',
      ),
      // Un logger que SÍ registra todo (el de los otros tests es mudo): para vigilar la privacidad.
      logger: AppLogger(
        logger: Logger(
          filter: ProductionFilter(),
          level: Level.trace,
          printer: SimplePrinter(),
          output: salidaDeLogs,
        ),
      ),
    );
    casoDeUso = RegistrarResultadoVisitaUseCase(
      repositorio,
      generarId: () => 'id-${++ids}',
      ahora: () => reloj,
    );
    await sembrarEdificio(db);
  });
  tearDown(() => db.close());

  Future<Either<Failure, ResultadoVisitaRegistrado>> registrar(
    _R resultado, {
    String vinculo = 'ep-1',
    String colportor = 'col-1',
    String? agendaId,
    String? jornadaId,
    String nota = '',
    IdsResultadoVisita? formulario,
  }) => casoDeUso(
    RegistrarResultadoVisitaParams(
      ids: formulario ?? casoDeUso.nuevosIds(),
      espacioPersonaId: vinculo,
      colportorId: colportor,
      resultado: resultado,
      agendaId: agendaId,
      jornadaId: jornadaId,
      nota: nota,
    ),
  );

  ResultadoVisitaRegistrado salio(Either<Failure, ResultadoVisitaRegistrado> r) =>
      r.fold((f) => throw StateError('falló: $f'), (registrado) => registrado);

  Future<List<VisitaFila>> visitas() => db.select(db.visitas).get();
  Future<List<AgendaFila>> agendas() => db.select(db.agendas).get();
  Future<List<NotaFila>> notas() => db.select(db.notas).get();
  Future<List<String>> colores() async => [
    for (final h in await db.select(db.houseStatuses).get()) h.color,
  ];
  List<String> cola() => [for (final c in encolador.encolados) '${c.entidad}:${c.operacion.name}'];
  Future<List<String>> todo() async => [
    for (final v in await visitas()) 'v:${v.id}:${v.tipoResultado}',
    for (final a in await agendas()) 'a:${a.id}:${a.estado}:${a.visitaId}',
    for (final n in await notas()) 'n:${n.id}',
    ...await colores(),
  ];
  String logs() => salidaDeLogs.buffer.expand((e) => e.lines).join('\n');

  group('Criterio 1: matriz resultado × (sin agenda | con agenda)', () {
    // (resultado, color de la casa, ¿cumple la agenda?)
    final casos = <(_R, String?, bool)>[
      (_R.venta, null, true),
      (_R.noContesto, 'SIN_CONTESTAR', false),
      (_R.rechazo, 'RECHAZO', true),
      (_R.entrevista, 'ENTREVISTA_SIN_VENTA', true),
    ];
    for (final (resultado, color, cumple) in casos) {
      test('dado ${resultado.codigo} sin agenda previa, la visita nace con su agenda COMPLETADA y '
          'sube visita, agenda y color en este orden', () async {
        final r = salio(await registrar(resultado));

        expect(r.guardada.aviso, isNull);
        expect((await visitas()).single.tipoResultado, resultado.codigo);
        expect((await agendas()).map((a) => (a.estado, a.visitaId)), [('COMPLETADA', 'id-1')]);
        expect(await colores(), color == null ? isEmpty : [color]);
        expect(cola().take(2), ['visita:insert', 'agenda:insert']);
        expect(cola().where((c) => c == 'visita:insert'), hasLength(1));
      });

      test(
        'dado ${resultado.codigo} con la agenda de la casa, ${cumple ? 'la agenda se cumple y '
                  'apunta a la visita' : 'la agenda sigue PENDIENTE y avisa qué hacer'}',
        () async {
          await repositorio.agendar(agendaDe('age-1'));
          encolador.encolados.clear();

          final r = salio(await registrar(resultado, agendaId: 'age-1'));

          final agenda = (await agendas()).single;
          expect((await visitas()).single.tipoResultado, resultado.codigo);
          expect(agenda.id, 'age-1');
          if (cumple) {
            expect([agenda.estado, agenda.visitaId], ['COMPLETADA', 'id-1']);
            expect(r.guardada.aviso, isNull);
            expect(cola(), contains('visita:insert'));
            expect(cola(), contains('agenda:update'));
          } else {
            expect([agenda.estado, agenda.visitaId], ['PENDIENTE', null]);
            expect(r.guardada.agendaQuedoPendiente, isTrue);
            expect(r.guardada.aviso, isNotNull);
            expect(cola(), isNot(contains('agenda:update')));
          }
          // Una agenda solo se crea cuando no había (nunca de más).
          expect(await agendas(), hasLength(1));
        },
      );
    }

    test(
      'NO_CONTESTO con agenda pendiente: la casa queda con el color de la agenda (entrevista programada), no gris '
      '(documenta P1 de #151: la HU pide gris + NO_CUMPLIDA y espera a Cristian)',
      () async {
        await repositorio.agendar(agendaDe('age-1'));

        await registrar(_R.noContesto, agendaId: 'age-1');

        expect(await colores(), ['ENTREVISTA_PROGRAMADA']);
      },
    );
  });

  group('Criterio 3: el aviso guía (qué pasó y qué hacer)', () {
    test(
      'el aviso de la agenda pendiente dice el texto fijado por la decisión del orquestador del '
      '23/10 (sin explicar limitaciones internas)',
      () {
        expect(
          VisitaGuardada.avisoAgendaPendiente,
          'Guardamos la visita. La agenda de esta casa sigue pendiente: si ya no va, cancelala '
          'desde Agendados.',
        );
      },
      skip:
          'QA #410: el aviso sigue con el texto viejo ("...porque todavía no se puede marcar como '
          'no cumplida...") y no con el que fijó la decisión del 23/10',
    );

    test('el aviso de P3 (sin persona) llega en el campo persona y dice qué hacer', () async {
      final r = await registrar(_R.rechazo, vinculo: '');
      final falla = r.swap().getOrElse(() => throw StateError('debía fallar'));

      expect(
        (falla as FailureValidacion).campos['persona'],
        'Elegí a la persona de la visita para guardar el resultado.',
      );
    });

    for (final motivo in MotivoAgendaIgnorada.values) {
      test('el aviso ${motivo.name} dice que la visita quedó guardada', () {
        expect(motivo.aviso, contains('guardamos la visita igual'));
      });
    }

    test('agenda inexistente, ajena o cerrada: la visita se guarda, la agenda no se toca y el '
        'aviso sale con el motivo', () async {
      await repositorio.agendar(agendaDe('ajena', vinculo: 'ep-2'));
      await repositorio.agendar(agendaDe('cerrada', estado: EstadoAgenda.completada));
      final esperado = {
        'no-existe': MotivoAgendaIgnorada.inexistente,
        'ajena': MotivoAgendaIgnorada.deOtraPersona,
        'cerrada': MotivoAgendaIgnorada.cerrada,
      };
      for (final MapEntry(key: agenda, value: motivo) in esperado.entries) {
        final r = salio(await registrar(_R.noContesto, agendaId: agenda));
        expect(r.guardada.agendaIgnorada, motivo, reason: agenda);
        expect(r.guardada.agendaQuedoPendiente, isFalse, reason: agenda);
      }
      expect((await visitas()).length, 3);
      final porId = {for (final a in await agendas()) a.id: a};
      expect(porId['ajena']!.estado, 'PENDIENTE');
      expect(porId['cerrada']!.estado, 'COMPLETADA');
      expect(porId['cerrada']!.visitaId, isNull);
    });
  });

  group('Criterio 4: validación de entradas', () {
    for (final vacio in ['', ' ', '   ', '\t', '\n  \n']) {
      test('persona "${vacio.replaceAll('\n', '\\n').replaceAll('\t', '\\t')}" no se acepta y no '
          'toca nada', () async {
        final r = await registrar(_R.entrevista, vinculo: vacio);

        expect(r.isLeft(), isTrue);
        expect(await todo(), isEmpty);
        expect(cola(), isEmpty);
      });

      test('colportor "${vacio.replaceAll('\n', '\\n').replaceAll('\t', '\\t')}" no se acepta y no '
          'toca nada', () async {
        final r = await registrar(_R.entrevista, colportor: vacio);

        expect(r.isLeft(), isTrue);
        expect(await todo(), isEmpty);
      });
    }

    test('un vínculo que no existe no guarda nada y señala el campo persona', () async {
      final r = await registrar(_R.venta, vinculo: 'ep-que-no-existe');

      final falla = r.swap().getOrElse(() => throw StateError('debía fallar'));
      expect((falla as FailureValidacion).campos.keys, ['persona']);
      expect(await todo(), isEmpty);
    });

    test('agenda y jornada en blanco equivalen a "sin agenda" y "sin jornada"', () async {
      final r = salio(await registrar(_R.entrevista, agendaId: '   ', jornadaId: '  '));

      expect(r.guardada.aviso, isNull);
      expect((await visitas()).single.jornadaId, isNull);
      expect((await agendas()).single.id, 'age-esp-1');
    });

    test('la jornada abierta queda en la visita (opcional, como en el servidor)', () async {
      await registrar(_R.entrevista, jornadaId: ' jor-1 ');

      expect((await visitas()).single.jornadaId, 'jor-1');
    });

    test('nota solo con espacios, saltos y tabs no crea ninguna nota', () async {
      await registrar(_R.rechazo, nota: ' \n\t   \n ');

      expect(await notas(), isEmpty);
      expect((await visitas()), hasLength(1));
    });

    test(
      'nota con emoji, comillas, SQL y caracteres de otro alfabeto se guarda tal cual',
      () async {
        const texto =
            "Dijo 'volvé mañana' 🙏🏽 \"ok\"; DROP TABLE visita;-- 你好 ñandú <b>x</b> %_\\";

        await registrar(_R.rechazo, nota: texto);

        expect((await notas()).single.texto, texto);
        expect(await visitas(), hasLength(1));
      },
    );

    test('una nota pegada de 200 mil caracteres no rompe el guardado ni la cola', () async {
      final enorme = 'ñ' * 200000;

      final r = await registrar(_R.entrevista, nota: enorme);

      expect(r.isRight(), isTrue);
      expect((await notas()).single.texto, hasLength(200000));
      expect(
        encolador.encolados.map((c) => jsonEncode(c.payload).length),
        everyElement(lessThan(2000)),
      );
    });

    test('los ids con espacios se limpian y el reintento sigue siendo el mismo registro', () async {
      const conEspacios = IdsResultadoVisita(visita: ' v-1 ', nota: ' n-1 ');
      await registrar(_R.rechazo, nota: 'x', formulario: conEspacios);
      await registrar(
        _R.rechazo,
        nota: 'x',
        formulario: const IdsResultadoVisita(visita: 'v-1', nota: 'n-1'),
      );

      expect((await visitas()).map((v) => v.id), ['v-1']);
      expect((await notas()).map((n) => n.id), ['n-1']);
    });
  });

  group('Criterio 5b: casos límite del flujo', () {
    test('si la acción falla a mitad, no queda nada a medias y el reintento con los mismos ids '
        'funciona (agenda existente, NO_CONTESTO)', () async {
      await repositorio.agendar(agendaDe('age-1'));
      encolador.encolados.clear();
      final formulario = casoDeUso.nuevosIds();
      encolador
        ..fallarCon = StateError('motor apagado')
        ..fallarDespuesDe = 0;

      final falla = await registrar(_R.noContesto, agendaId: 'age-1', formulario: formulario);

      expect(falla.isLeft(), isTrue);
      expect(await visitas(), isEmpty);
      expect((await agendas()).single.estado, 'PENDIENTE');
      expect(await colores(), ['ENTREVISTA_PROGRAMADA']);

      encolador.fallarCon = null;
      final bien = salio(await registrar(_R.noContesto, agendaId: 'age-1', formulario: formulario));

      expect(bien.guardada.agendaQuedoPendiente, isTrue);
      expect(await visitas(), hasLength(1));
    });

    test('la falla de a mitad devuelve un Failure con el que se puede reintentar (sin excepción '
        'sin atrapar)', () async {
      encolador
        ..fallarCon = StateError('motor apagado')
        ..fallarDespuesDe = 1;

      final falla = await registrar(_R.rechazo, nota: 'n');

      expect(falla.isLeft(), isTrue);
      expect(await todo(), isEmpty);
    });

    test('cinco registros a la vez sobre la misma agenda: uno la cumple, los otros cuatro quedan '
        'como espontáneos con el aviso "cerrada" y nada se pierde', () async {
      await repositorio.agendar(agendaDe('age-1'));

      final rs = await Future.wait([
        for (var i = 0; i < 5; i++) registrar(_R.entrevista, agendaId: 'age-1'),
      ]);

      final avisos = [for (final r in rs) salio(r).guardada.agendaIgnorada];
      expect(avisos.where((a) => a == null), hasLength(1));
      expect(avisos.where((a) => a == MotivoAgendaIgnorada.cerrada), hasLength(4));
      expect(await visitas(), hasLength(5));
      expect(await agendas(), hasLength(5));
      expect(
        (await agendas()).where((a) => a.estado == 'COMPLETADA' && a.visitaId != null),
        hasLength(5),
      );
      expect(await colores(), hasLength(1));
    });

    test(
      'doble tap en NO_CONTESTO sobre una agenda: las dos respuestas guardan una sola visita',
      () async {
        await repositorio.agendar(agendaDe('age-1'));
        final formulario = casoDeUso.nuevosIds();

        final rs = await Future.wait([
          registrar(_R.noContesto, agendaId: 'age-1', formulario: formulario),
          registrar(_R.noContesto, agendaId: 'age-1', formulario: formulario),
        ]);

        expect(rs.every((r) => r.isRight()), isTrue);
        expect(await visitas(), hasLength(1));
        expect((await agendas()).single.estado, 'PENDIENTE');
      },
    );

    test(
      'doble tap en NO_CONTESTO sobre una agenda: la respuesta repetida también trae el aviso de '
      'la agenda pendiente (la pantalla puede quedarse con cualquiera de las dos)',
      () async {
        await repositorio.agendar(agendaDe('age-1'));
        final formulario = casoDeUso.nuevosIds();

        final rs = await Future.wait([
          registrar(_R.noContesto, agendaId: 'age-1', formulario: formulario),
          registrar(_R.noContesto, agendaId: 'age-1', formulario: formulario),
        ]);

        expect(rs.map((r) => salio(r).guardada.aviso), everyElement(isNotNull));
      },
      skip:
          'QA #410: el segundo toque (visita que ya estaba) vuelve sin aviso ni agendaQuedoPendiente: '
          'si la pantalla usa esa respuesta, la colportora no se entera de que la agenda sigue pendiente',
    );

    test('reintento con los mismos ids tras un éxito (la respuesta se perdió): un solo registro y '
        'el seguimiento de VENTA se conserva', () async {
      final formulario = casoDeUso.nuevosIds();
      await registrar(_R.venta, formulario: formulario);

      final otra = salio(await registrar(_R.venta, formulario: formulario));

      expect(otra.seguimiento, SeguimientoDeVisita.venta);
      expect(await visitas(), hasLength(1));
      expect(await agendas(), hasLength(1));
      expect(cola().where((c) => c == 'visita:insert'), hasLength(1));
    });

    test('reentrar y registrar de nuevo la misma casa: cada visita tiene sus ids y la casa tiene '
        'una sola fila de color', () async {
      for (final r in [_R.noContesto, _R.noContesto, _R.rechazo, _R.noContesto]) {
        await registrar(r);
        reloj = reloj.add(const Duration(minutes: 7));
      }

      expect(await visitas(), hasLength(4));
      expect((await visitas()).map((v) => v.id).toSet(), hasLength(4));
      expect(await colores(), hasLength(1));
    });

    test('muchos registros seguidos (60) en edificios distintos no pisan nada', () async {
      for (var i = 0; i < 60; i++) {
        await registrar(_R.values[i % _R.values.length], vinculo: i.isEven ? 'ep-1' : 'ep-2');
      }

      expect(await visitas(), hasLength(60));
      expect(await agendas(), hasLength(60));
      expect(await colores(), hasLength(1));
    });

    test('la fecha de la visita es el instante del reloj, en UTC', () async {
      final r = salio(await registrar(_R.entrevista));

      expect(r.guardada.visita.fecha.isUtc, isTrue);
      expect(r.guardada.visita.fecha, reloj.toUtc());
      expect((await visitas()).single.fecha, reloj.toUtc());
    });
  });

  group('Criterio 8: privacidad', () {
    const secreto = 'Sra. Gómez, 099 123 456, vive sola';

    test('la nota no sale en ningún log (alta, aviso de agenda, falla) ni en toString', () async {
      await repositorio.agendar(agendaDe('age-1'));
      final params = RegistrarResultadoVisitaParams(
        ids: casoDeUso.nuevosIds(),
        espacioPersonaId: 'ep-1',
        colportorId: 'col-1',
        resultado: _R.noContesto,
        agendaId: 'age-1',
        nota: secreto,
      );
      final r = salio(await casoDeUso(params));
      await registrar(_R.rechazo, agendaId: 'no-existe', nota: secreto);
      encolador
        ..fallarCon = StateError('motor apagado')
        ..fallarDespuesDe = 1;
      final falla = await registrar(_R.rechazo, nota: secreto);

      for (final texto in [
        logs(),
        '$params',
        '$r',
        '${r.guardada}',
        '${r.guardada.visita}',
        '$falla',
      ]) {
        expect(texto, isNot(contains('Gómez')));
        expect(texto, isNot(contains('099')));
      }
    });

    test(
      'la cola de sync solo lleva visita, agenda y house_status, sin el texto de la nota',
      () async {
        await repositorio.agendar(agendaDe('age-1'));
        encolador.encolados.clear();

        await registrar(_R.rechazo, agendaId: 'age-1', nota: secreto);

        expect(cola().toSet().map((c) => c.split(':').first), isNot(contains('nota')));
        for (final c in encolador.encolados) {
          final json = jsonEncode(c.payload);
          expect(json, isNot(contains('Gómez')));
          expect(c.payload.keys, isNot(contains('texto')));
          expect(c.payload.keys, isNot(contains('nota')));
        }
      },
    );

    test(
      'el payload de la visita sube el resultado con su código (sin campo extra de presentación)',
      () async {
        await registrar(_R.entrevista);

        final visita = encolador.encolados.firstWhere((c) => c.entidad == 'visita').payload;
        expect(visita['tipo_resultado'], 'ENTREVISTA');
        expect(visita.keys, isNot(contains('cuenta_como_presentacion')));
        expect(visita.keys.where((k) => k.contains('presentacion')), isEmpty);
      },
    );

    test(
      'los logs del alta con agenda pendiente llevan solo ids y el código del resultado',
      () async {
        await repositorio.agendar(agendaDe('age-1'));

        await registrar(_R.noContesto, agendaId: 'age-1', nota: secreto);

        expect(logs(), contains('VISITA_ALTA_AGENDA_PENDIENTE'));
        expect(logs(), isNot(contains(secreto)));
      },
    );
  });

  group('Presentación (docs#69)', () {
    test('cuentan VENTA y ENTREVISTA; no NO_CONTESTO, RECHAZO (a confirmar, S62) ni nada más', () {
      expect(
        {for (final r in _R.values) r.codigo: r.cuentaComoPresentacion},
        {'VENTA': true, 'NO_CONTESTO': false, 'RECHAZO': false, 'ENTREVISTA': true},
      );
    });

    test('cada resultado se reconoce por su código y los códigos no se repiten', () {
      for (final r in _R.values) {
        expect(_R.desdeCodigo(r.codigo), r);
      }
      expect(_R.values.map((r) => r.codigo).toSet(), hasLength(_R.values.length));
      expect(() => _R.desdeCodigo('COBRANZA'), throwsArgumentError);
    });
  });

  group('Escenarios de la HU, fila por fila', () {
    test(
      'NO_CONTESTO + agenda: la HU pide NO_CUMPLIDA y gris (documentado: espera P1 de #151)',
      () async {
        await repositorio.agendar(agendaDe('age-1'));

        await registrar(_R.noContesto, agendaId: 'age-1');

        // Hoy: PENDIENTE y color de la agenda. No es un hallazgo del PR: la decisión es de Cristian.
        final agenda = (await agendas()).single;
        expect(EstadoAgenda.desdeCodigo(agenda.estado), EstadoAgenda.pendiente);
      },
    );

    test('RECHAZO con nota opcional: casa roja', () async {
      await registrar(_R.rechazo, nota: 'No quiere');
      expect(await colores(), ['RECHAZO']);
    });

    test(
      'tres visitas del día (VENTA, ENTREVISTA, NO_CONTESTO): el servidor cuenta 2 por código',
      () async {
        await registrar(_R.venta, vinculo: 'ep-1');
        await registrar(_R.entrevista, vinculo: 'ep-2');
        await registrar(_R.noContesto, vinculo: 'ep-2');

        final subidas = encolador.encolados
            .where((c) => c.entidad == 'visita')
            .map((c) => _R.desdeCodigo(c.payload['tipo_resultado'] as String))
            .where((t) => t.cuentaComoPresentacion);
        expect(subidas, hasLength(2));
      },
    );
  });
}
