// Registrar el resultado de una visita (HU-VIS-005, #410) de punta a punta contra la DB real en
// memoria: el caso de uso, el repositorio, las tablas `visita`/`agenda`/`nota`/`house_status`, el
// servicio real del color de la casa y la cola de sync. Los escenarios llevan el título de la HU.
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/agenda_repository_impl.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita_guardada.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/registrar_resultado_visita_use_case.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

typedef _R = TipoResultadoVisita;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late AgendaRepositoryImpl repositorio;
  late RegistrarResultadoVisitaUseCase casoDeUso;
  var ids = 0;
  var reloj = t0;

  setUp(() async {
    ids = 0;
    reloj = t0.add(const Duration(minutes: 5));
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    var espontaneas = 0;
    repositorio = AgendaRepositoryImpl(
      AgendaLocalDataSourceDrift(
        db,
        encolador: encolador,
        estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
        generarId: () => 'age-esp-${++espontaneas}',
      ),
      logger: loggerMudo(),
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
    String espacio = 'esp-1',
    String? vinculo = 'ep-1',
    String? agendaId,
    String nota = '',
    IdsResultadoVisita? formulario,
  }) => casoDeUso(
    RegistrarResultadoVisitaParams(
      ids: formulario ?? casoDeUso.nuevosIds(),
      espacioId: espacio,
      espacioPersonaId: vinculo,
      colportorId: 'col-1',
      resultado: resultado,
      agendaId: agendaId,
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

  group('Escenario: Registrar NO_CONTESTO', () {
    test('dado que nadie contestó y no había agenda, cuando registro NO_CONTESTO, la casa queda '
        'gris y la visita nace con su agenda cumplida, todo en una transacción', () async {
      final r = salio(await registrar(_R.noContesto));

      expect(r.guardada.aviso, isNull);
      expect((await visitas()).map((v) => (v.id, v.tipoResultado)), [('id-1', 'NO_CONTESTO')]);
      expect((await agendas()).map((a) => (a.estado, a.visitaId)), [('CUMPLIDA', 'id-1')]);
      expect(await colores(), ['SIN_CONTESTAR']);
      expect(cola(), ['visita:insert', 'agenda:insert', 'house_status:insert']);
    });

    test(
      'dado que la casa tenía una agenda, cuando registro NO_CONTESTO, la visita se guarda y la '
      'agenda pasa a NO_CUMPLIDA apuntando a la visita (decisión «No cumplida», 23/10)',
      () async {
        await repositorio.agendar(agendaDe('age-1'));
        encolador.encolados.clear();

        final r = salio(await registrar(_R.noContesto, agendaId: 'age-1'));

        expect(r.guardada.agendaNoCumplida, isTrue);
        expect(r.guardada.aviso, isNull);
        expect((await visitas()).single.tipoResultado, 'NO_CONTESTO');
        expect((await agendas()).map((a) => (a.id, a.estado, a.visitaId)), [
          ('age-1', 'NO_CUMPLIDA', 'id-1'),
        ]);
        expect(cola(), ['visita:insert', 'agenda:update', 'house_status:update']);
      },
    );
  });

  group('Escenario: Registrar RECHAZO', () {
    test('dado que el cliente rechazó, cuando registro RECHAZO con nota opcional, la casa queda '
        'roja y la nota se queda en el teléfono, fuera del sync', () async {
      await registrar(_R.rechazo, nota: '  No quiere que vuelvan  ');

      expect(await colores(), ['RECHAZO']);
      final nota = (await notas()).single;
      expect(
        [nota.targetType, nota.targetId, nota.texto],
        ['VISITA', 'id-1', 'No quiere que vuelvan'],
      );
      expect(
        encolador.encolados.map((c) => c.payload.toString()),
        everyElement(isNot(contains('No quiere'))),
      );
    });

    test('dado un RECHAZO sin nota, cuando se registra, no se crea ninguna nota', () async {
      await registrar(_R.rechazo);

      expect(await notas(), isEmpty);
    });

    test(
      'dado un RECHAZO con la agenda de la casa, cuando se registra, la agenda se cumple y apunta '
      'a la visita',
      () async {
        await repositorio.agendar(agendaDe('age-1'));

        await registrar(_R.rechazo, agendaId: 'age-1');

        expect((await agendas()).map((a) => (a.estado, a.visitaId)), [('CUMPLIDA', 'id-1')]);
        expect(await colores(), ['RECHAZO']);
      },
    );
  });

  group('Escenario: Edge -registrar resultado sin agenda previa (visita espontánea)', () {
    test('dado que paso por una ubicación sin agenda, cuando registro resultado, se crea la agenda '
        'cumplida y el resultado en una sola transacción', () async {
      final r = salio(await registrar(_R.entrevista));

      expect(r.guardada.agendaIgnorada, isNull);
      expect(await todo(), [
        'v:id-1:ENTREVISTA',
        'a:age-esp-1:CUMPLIDA:id-1',
        'ENTREVISTA_SIN_VENTA',
      ]);
    });

    for (final n in [0, 1, 2]) {
      test('si el encolado falla en el job $n no queda nada y el reintento con los mismos ids deja '
          'una visita y una agenda', () async {
        final formulario = casoDeUso.nuevosIds();
        encolador
          ..fallarCon = StateError('motor apagado')
          ..fallarDespuesDe = n;

        final falla = await registrar(_R.entrevista, nota: 'una nota', formulario: formulario);

        expect(falla.isLeft(), isTrue);
        expect(await todo(), isEmpty);

        encolador.fallarCon = null;
        final bien = await registrar(_R.entrevista, nota: 'una nota', formulario: formulario);

        expect(bien.isRight(), isTrue);
        expect((await visitas()).map((v) => v.id), ['id-1']);
        expect((await agendas()).map((a) => (a.estado, a.visitaId)), [('CUMPLIDA', 'id-1')]);
        expect((await notas()).map((x) => x.id), ['id-2']);
        expect(await colores(), ['ENTREVISTA_SIN_VENTA']);
      });
    }
  });

  group('Escenario: La entrevista hecha cuenta como presentación', () {
    test(
      'dado tres visitas hoy (VENTA, ENTREVISTA y NO_CONTESTO), cuando se cuentan como las cuenta '
      'el servidor, son 2 presentaciones y la visita sin respuesta no cuenta',
      () async {
        await registrar(_R.venta);
        await registrar(_R.entrevista, espacio: 'esp-2', vinculo: 'ep-2');
        await registrar(_R.noContesto, espacio: 'esp-2', vinculo: 'ep-2');

        final guardadas = [
          for (final v in await visitas()) TipoResultadoVisita.desdeCodigo(v.tipoResultado),
        ];
        expect(guardadas.where((t) => t.cuentaComoPresentacion), hasLength(2));
        // Lo que sube al servidor distingue el resultado por su código, sin ningún campo aparte.
        expect(
          encolador.encolados
              .where((c) => c.entidad == 'visita')
              .map((c) => c.payload['tipo_resultado']),
          ['VENTA', 'ENTREVISTA', 'NO_CONTESTO'],
        );
      },
    );
  });

  group('VENTA: el punto de enganche con la venta (S9)', () {
    test(
      'dado un VENTA, cuando se registra, la visita se guarda y el seguimiento dice que sigue la '
      'venta; la casa no se pinta hasta que exista la venta',
      () async {
        final r = salio(await registrar(_R.venta));

        expect(r.seguimiento, SeguimientoDeVisita.venta);
        expect((await visitas()).single.tipoResultado, 'VENTA');
        expect(await colores(), isEmpty);
      },
    );

    test('dado cualquier otro resultado, cuando se registra, no sigue nada', () async {
      for (final resultado in [_R.noContesto, _R.rechazo, _R.entrevista]) {
        expect(salio(await registrar(resultado)).seguimiento, SeguimientoDeVisita.ninguno);
      }
    });
  });

  group('Casos límite del guardado', () {
    test(
      'dado un doble tap (el mismo formulario enviado dos veces a la vez), cuando termina, hay una '
      'sola visita y una sola agenda',
      () async {
        final formulario = casoDeUso.nuevosIds();

        final rs = await Future.wait([
          registrar(_R.rechazo, nota: 'n', formulario: formulario),
          registrar(_R.rechazo, nota: 'n', formulario: formulario),
        ]);

        expect(rs.every((r) => r.isRight()), isTrue);
        expect((await visitas()).length, 1);
        expect((await agendas()).length, 1);
        expect((await notas()).length, 1);
        expect(cola().where((c) => c == 'visita:insert'), hasLength(1));
      },
    );

    test(
      'dado dos resultados seguidos sobre la misma agenda, sin esperar al primero, el segundo se '
      'guarda como espontáneo con su aviso y no pisa a la primera',
      () async {
        await repositorio.agendar(agendaDe('age-1'));

        final rs = await Future.wait([
          registrar(_R.entrevista, agendaId: 'age-1'),
          registrar(_R.rechazo, agendaId: 'age-1'),
        ]);

        final avisos = rs.map((r) => salio(r).guardada.agendaIgnorada).toList();
        expect(avisos, [null, MotivoAgendaIgnorada.cerrada]);
        expect((await visitas()).length, 2);
        final agenda = (await agendas()).firstWhere((a) => a.id == 'age-1');
        expect([agenda.estado, agenda.visitaId], ['CUMPLIDA', 'id-1']);
        expect((await agendas()).length, 2);
      },
    );

    test('dado que se vuelve atrás y se reabre el formulario, cuando se registra otra vez, es otra '
        'visita con otros ids y no pisa a la anterior', () async {
      await registrar(_R.noContesto);
      reloj = reloj.add(const Duration(hours: 2));

      await registrar(_R.noContesto);

      expect((await visitas()).map((v) => v.id), ['id-1', 'id-3']);
    });

    test('dado el vínculo de otro depto del edificio, cuando se registra, la casa se pinta por el '
        'resultado', () async {
      await registrar(_R.rechazo, espacio: 'esp-2', vinculo: 'ep-2');

      expect(await colores(), ['RECHAZO']);
      expect((await visitas()).single.espacioPersonaId, 'ep-2');
    });

    test(
      'dado una persona dada de baja, cuando se registra, no se guarda nada y dice qué hacer',
      () async {
        await (db.update(
          db.espacioPersonas,
        )..where((v) => v.id.equals('ep-1'))).write(EspacioPersonasCompanion(deletedAt: Value(t0)));

        final r = await registrar(_R.rechazo);

        final falla = r.swap().getOrElse(() => throw StateError('debía fallar'));
        expect((falla as FailureValidacion).campos.keys, ['persona']);
        expect(await todo(), isEmpty);
      },
    );

    test('dado que no se eligió a la persona, cuando se registra, la visita queda en la casa sin '
        'persona (decisión «Sin persona», 23/10)', () async {
      final r = await registrar(_R.noContesto, vinculo: '');

      expect(r.isRight(), isTrue);
      final v = (await visitas()).single;
      expect([v.espacioId, v.espacioPersonaId], ['esp-1', null]);
      expect(cola(), contains('visita:insert'));
    });

    test(
      'dado un espacio que no está en el teléfono, cuando se registra, no se guarda nada',
      () async {
        final r = await registrar(_R.noContesto, espacio: 'esp-que-no-llego', vinculo: null);

        expect(
          (r.swap().getOrElse(() => throw StateError('debía fallar')) as FailureValidacion)
              .campos
              .keys,
          ['espacio'],
        );
        expect(await todo(), isEmpty);
        expect(cola(), isEmpty);
      },
    );

    test('dado una nota larga y con tildes, cuando se registra, se guarda entera', () async {
      final larga = List.generate(300, (i) => 'Atiende ñandú $i, volver mañana').join('\n');

      await registrar(_R.entrevista, nota: larga);

      expect((await notas()).single.texto, larga);
    });
  });
}
