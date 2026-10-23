// QA de BACK-HU-VIS-001 (#404): la agenda, las visitas y el color de la casa en el teléfono, sin
// vista. Cubre lo que los tests del PR no cruzan: privacidad de la nota en cola y logs, falla a
// mitad de la acción en cada paso del encolado, muchas filas en una casa y secuencias de acciones
// superpuestas con un invariante (la cache siempre dice lo que dicen las tablas y la cola siempre
// llega a la misma conclusión). Todo contra la DB real en memoria, con el repositorio real.
import 'dart:convert';
import 'dart:math';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/agenda_repository_impl.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:dartz/dartz.dart' hide State;
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:logger/logger.dart';
import 'package:test/test.dart';

import '../../../../../helpers/campo_falsos.dart';
import '../../../../../helpers/logger_mudo.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late AgendaLocalDataSourceDrift local;
  late AgendaRepositoryImpl repo;
  late MemoryOutput salidaDeLogs;

  /// Todo lo que el repositorio escribió en los logs, como un solo texto.
  String logs() => salidaDeLogs.buffer.expand((e) => e.lines).join('\n');

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    local = AgendaLocalDataSourceDrift(
      db,
      encolador: encolador,
      estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
    );
    salidaDeLogs = MemoryOutput();
    repo = AgendaRepositoryImpl(
      local,
      logger: AppLogger(
        logger: Logger(level: Level.all, printer: SimplePrinter(), output: salidaDeLogs),
      ),
    );
    await sembrarCasa(db);
  });
  tearDown(() => db.close());

  Future<Map<String, List<String>>> instantanea() async => {
    'agenda': [for (final f in await db.select(db.agendas).get()) jsonEncode(f.toJson())],
    'visita': [for (final f in await db.select(db.visitas).get()) jsonEncode(f.toJson())],
    'nota': [for (final f in await db.select(db.notas).get()) jsonEncode(f.toJson())],
    'house_status': [
      for (final f in await db.select(db.houseStatuses).get()) jsonEncode(f.toJson()),
    ],
  };

  group('privacidad de la nota (local-only, ADR-017)', () {
    const secreto = 'SECRETO ñandú 🔒 099123456 (calle Mataojo 2044)';

    test('la nota de una agenda y la de una visita se guardan tal cual y no salen del teléfono '
        '(ni a la cola, ni a las filas que suben, ni a los logs)', () async {
      await repo.agendar(agendaDe('age-1'), nota: notaDe('not-1', texto: secreto));
      await repo.registrarVisita(
        visitaDe('vis-1', creada: t0.add(const Duration(minutes: 5))),
        agendaId: 'age-1',
        nota: notaDe('not-2', texto: secreto),
      );

      final notas = await db.select(db.notas).get();
      expect(notas.map((n) => n.texto), [secreto, secreto]);
      expect(notas.map((n) => (n.targetType, n.targetId)).toSet(), {
        ('AGENDA', 'age-1'),
        ('VISITA', 'vis-1'),
      });
      final subida = jsonEncode([
        for (final c in encolador.encolados)
          {'e': c.entidad, 'o': c.operacion.name, 'p': c.payload},
      ]);
      expect(subida, isNot(contains('SECRETO')));
      expect(subida, isNot(contains('099123456')));
      expect(subida, isNot(contains('Mataojo')));
      final filas = jsonEncode([
        for (final a in await db.select(db.agendas).get()) a.toJson(),
        for (final v in await db.select(db.visitas).get()) v.toJson(),
        for (final h in await db.select(db.houseStatuses).get()) h.toJson(),
      ]);
      expect(filas, isNot(contains('SECRETO')));
      expect(logs(), isNot(contains('SECRETO')));
      expect(logs(), isNot(contains('099123456')));
    });

    test('si la escritura falla con la nota ya adentro (nota con id repetido), la falla y los '
        'logs no repiten ni el texto ni la sentencia, y no queda nada a medias', () async {
      await db
          .into(db.notas)
          .insert(
            NotasCompanion.insert(
              id: 'not-dup',
              targetType: 'PERSONA',
              targetId: 'per-1',
              texto: 'nota previa',
              createdAt: t0,
              updatedAt: t0,
            ),
          );
      final antes = await instantanea();

      final r = await repo.agendar(agendaDe('age-1'), nota: notaDe('not-dup', texto: secreto));

      final falla = r.fold((f) => f, (_) => fail('debía fallar'));
      expect(falla, isA<FailureInesperado>());
      for (final texto in [falla.toString(), logs()]) {
        expect(texto, isNot(contains('SECRETO')));
        expect(texto, isNot(contains('099123456')));
        expect(texto.toUpperCase(), isNot(contains('INSERT INTO')));
      }
      expect(await instantanea(), antes);
    });

    test('textos límite: vacío, solo espacios, emoji y 200.000 caracteres se guardan tal cual '
        'y no rompen el recálculo del color', () async {
      final largo = 'á🙂' * 100000;
      final casos = {'n1': '', 'n2': '   \n\t ', 'n3': '🙂🙂🙂', 'n4': largo};
      var i = 0;
      for (final MapEntry(key: id, value: texto) in casos.entries) {
        final r = await repo.agendar(
          agendaDe('age-$id', creada: t0.add(Duration(minutes: ++i))),
          nota: notaDe(id, texto: texto),
        );
        expect(r.isRight(), isTrue, reason: 'nota "$id"');
      }
      final guardadas = {for (final n in await db.select(db.notas).get()) n.id: n.texto};
      expect(guardadas, casos);
      expect((await db.select(db.houseStatuses).get()).single.color, 'ENTREVISTA_PROGRAMADA');
    });
  });

  group('falla a mitad de la acción: o se guarda todo o no queda nada, y reintentar sale bien', () {
    Future<void> escenario() async {
      await repo.agendar(agendaDe('age-1'), nota: notaDe('not-0'));
    }

    // registrarVisita con agenda y nota encola 3 jobs: visita, agenda cumplida y color de la casa.
    for (final n in [0, 1, 2]) {
      test('registrarVisita con agenda y nota: el encolado falla en el job $n', () async {
        await escenario();
        final antes = await instantanea();
        encolador
          ..fallarCon = StateError('motor apagado')
          ..fallarDespuesDe = encolador.encolados.length + n;

        final r = await repo.registrarVisita(
          visitaDe(
            'vis-1',
            resultado: TipoResultadoVisita.rechazo,
            creada: t0.add(const Duration(minutes: 9)),
          ),
          agendaId: 'age-1',
          nota: notaDe('not-1'),
        );

        expect(r.isLeft(), isTrue);
        expect(await instantanea(), antes, reason: 'la transacción se revierte entera');

        encolador.fallarCon = null;
        final otra = await repo.registrarVisita(
          visitaDe(
            'vis-1',
            resultado: TipoResultadoVisita.rechazo,
            creada: t0.add(const Duration(minutes: 9)),
          ),
          agendaId: 'age-1',
          nota: notaDe('not-1'),
        );
        expect(otra.isRight(), isTrue, reason: 'el reintento con los mismos ids sale bien');
        expect((await db.select(db.visitas).get()).map((v) => v.id), ['vis-1']);
        expect((await db.select(db.agendas).get()).single.estado, 'COMPLETADA');
        expect((await db.select(db.agendas).get()).single.visitaId, 'vis-1');
        expect((await db.select(db.houseStatuses).get()).single.color, 'RECHAZO');
        expect((await db.select(db.notas).get()).map((x) => x.id).toSet(), {'not-0', 'not-1'});
      });
    }

    test(
      'cancelar: si falla el job del color, la agenda sigue pendiente y la casa amarilla',
      () async {
        await escenario();
        final antes = await instantanea();
        encolador
          ..fallarCon = StateError('motor apagado')
          ..fallarDespuesDe = encolador.encolados.length + 1;

        final r = await repo.cancelar('age-1', ahora: t0.add(const Duration(minutes: 3)));

        expect(r.isLeft(), isTrue);
        expect(await instantanea(), antes);
        encolador.fallarCon = null;
        expect(
          (await repo.cancelar('age-1', ahora: t0.add(const Duration(minutes: 3)))).isRight(),
          isTrue,
        );
        expect((await db.select(db.agendas).get()).single.estado, 'CANCELADA');
        expect((await db.select(db.houseStatuses).get()).single.deletedAt, isNotNull);
      },
    );
  });

  group('datos límite: muchas filas en una sola casa', () {
    test('un edificio de 40 deptos con 1.200 visitas y 300 agendas: el color sale bien y la '
        'acción siguiente no se vuelve lenta', () async {
      await db.delete(db.espacioPersonas).go();
      await db.delete(db.espacios).go();
      await db.batch((b) {
        for (var i = 0; i < 40; i++) {
          b.insert(
            db.espacios,
            EspaciosCompanion.insert(
              id: 'e$i',
              ubicacionId: 'ub-1',
              numeroDepto: Value('D$i'),
              createdAt: t0,
              updatedAt: t0,
            ),
          );
          b.insert(
            db.espacioPersonas,
            EspacioPersonasCompanion.insert(
              id: 'v$i',
              espacioId: 'e$i',
              personaId: 'p$i',
              createdAt: t0,
              updatedAt: t0,
            ),
          );
        }
      });
      for (var i = 0; i < 1200; i++) {
        await insertarVisita(
          db,
          visitaDe(
            'vm$i',
            vinculo: 'v${i % 40}',
            resultado: i.isEven ? TipoResultadoVisita.noContesto : TipoResultadoVisita.rechazo,
          ),
        );
      }
      for (var i = 0; i < 300; i++) {
        await insertarAgenda(
          db,
          agendaDe('am$i', vinculo: 'v${i % 40}', estado: EstadoAgenda.cancelada),
        );
      }

      final reloj = Stopwatch()..start();
      final r = await repo.agendar(
        agendaDe('age-nueva', vinculo: 'v7', creada: t0.add(const Duration(minutes: 1))),
      );
      reloj.stop();

      expect(r.isRight(), isTrue);
      expect((await db.select(db.houseStatuses).get()).single.color, 'ENTREVISTA_PROGRAMADA');
      expect(reloj.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });

  group('acciones superpuestas: la cache y la cola siempre cuentan lo mismo que las tablas', () {
    // Tres casas: un edificio con dos deptos (ub-1) y dos casas (ub-2, ub-3).
    const vinculos = {'ep-1': 'ub-1', 'ep-2': 'ub-1', 'ep-3': 'ub-2', 'ep-4': 'ub-3'};

    Future<void> sembrarTodo() async {
      await db.delete(db.espacioPersonas).go();
      await db.delete(db.espacios).go();
      await db.delete(db.ubicaciones).go();
      for (final id in ['ub-1', 'ub-2', 'ub-3']) {
        await sembrarUbicacion(db, id: id, tipo: id == 'ub-1' ? 'EDIFICIO' : 'CASA');
      }
      await sembrarEspacio(db, id: 'es-1', ubicacionId: 'ub-1', numeroDepto: '1A');
      await sembrarEspacio(db, id: 'es-2', ubicacionId: 'ub-1', numeroDepto: '2B');
      await sembrarEspacio(db, id: 'es-3', ubicacionId: 'ub-2');
      await sembrarEspacio(db, id: 'es-4', ubicacionId: 'ub-3');
      await sembrarVinculo(db, id: 'ep-1', espacioId: 'es-1', personaId: 'pe-1');
      await sembrarVinculo(db, id: 'ep-2', espacioId: 'es-2', personaId: 'pe-2');
      await sembrarVinculo(db, id: 'ep-3', espacioId: 'es-3', personaId: 'pe-3');
      await sembrarVinculo(db, id: 'ep-4', espacioId: 'es-4', personaId: 'pe-4');
    }

    /// El color que le toca a [ubicacion] según las tablas, calculado aparte del código del PR.
    Future<String?> esperado(String ubicacion) async {
      final prioridades = <int, String>{};
      final deLaCasa = vinculos.entries
          .where((e) => e.value == ubicacion)
          .map((e) => e.key)
          .toSet();
      for (final a in await db.select(db.agendas).get()) {
        if (deLaCasa.contains(a.espacioPersonaId) &&
            a.estado == 'PENDIENTE' &&
            a.deletedAt == null &&
            a.tipo == 'ENTREVISTA') {
          prioridades[3] = 'ENTREVISTA_PROGRAMADA';
        }
      }
      for (final v in await db.select(db.visitas).get()) {
        if (!deLaCasa.contains(v.espacioPersonaId) || v.deletedAt != null) continue;
        switch (v.tipoResultado) {
          case 'ENTREVISTA':
            prioridades[5] = 'ENTREVISTA_SIN_VENTA';
          case 'NO_CONTESTO':
            prioridades[6] = 'SIN_CONTESTAR';
          case 'RECHAZO':
            prioridades[7] = 'RECHAZO';
        }
      }
      if (prioridades.isEmpty) return null;
      return prioridades[prioridades.keys.reduce(min)];
    }

    for (final semilla in List.generate(12, (i) => 404 + i)) {
      test('secuencia al azar, semilla $semilla (rechazos y repeticiones incluidos)', () async {
        await sembrarTodo();
        final azar = Random(semilla);
        final agendasCreadas = <String>[];
        var reloj = 0;
        var contador = 0;
        DateTime ahora() => t0.add(Duration(seconds: ++reloj));

        Future<Either<Failure, Object>> unaAccion() {
          final vinculo = vinculos.keys.elementAt(azar.nextInt(vinculos.length));
          switch (azar.nextInt(6)) {
            case 0 || 1:
              final id = 'age-${++contador}';
              agendasCreadas.add(id);
              return repo.agendar(
                agendaDe(
                  id,
                  vinculo: vinculo,
                  tipo: azar.nextBool() ? TipoAgenda.entrevista : TipoAgenda.cobranza,
                  creada: ahora(),
                ),
                nota: azar.nextBool() ? notaDe('not-${++contador}') : null,
              );
            case 2:
              final id = agendasCreadas.isEmpty || azar.nextInt(5) == 0
                  ? 'age-que-no-existe'
                  : agendasCreadas[azar.nextInt(agendasCreadas.length)];
              return repo.cancelar(id, ahora: ahora());
            case 3:
              final id = agendasCreadas.isEmpty
                  ? 'age-1'
                  : agendasCreadas[azar.nextInt(agendasCreadas.length)];
              return repo.agendar(agendaDe(id, vinculo: vinculo, creada: ahora()));
            default:
              final resultado = TipoResultadoVisita.values[azar.nextInt(4)];
              final agendaId = agendasCreadas.isEmpty || azar.nextBool()
                  ? null
                  : agendasCreadas[azar.nextInt(agendasCreadas.length)];
              return repo.registrarVisita(
                visitaDe(
                  'vis-${++contador}',
                  vinculo: vinculo,
                  resultado: resultado,
                  creada: ahora(),
                ),
                agendaId: agendaId,
              );
          }
        }

        for (var tanda = 0; tanda < 14; tanda++) {
          await Future.wait([for (var i = 0; i < 1 + azar.nextInt(5); i++) unaAccion()]);
        }

        // 1. La cache dice lo que dicen las tablas.
        final filas = {for (final h in await db.select(db.houseStatuses).get()) h.ubicacionId: h};
        for (final ub in ['ub-1', 'ub-2', 'ub-3']) {
          final color = await esperado(ub);
          final fila = filas[ub];
          if (color == null) {
            expect(fila == null || fila.deletedAt != null, isTrue, reason: '$ub sin estado');
          } else {
            expect(fila?.deletedAt, isNull, reason: '$ub debía estar viva');
            expect(fila?.color, color, reason: ub);
          }
        }

        // 2. La cola cuenta lo mismo: cada fila empieza con su insert, no se inserta dos veces y
        // lo último que se encoló de cada casa es lo que quedó en la cache.
        final vistos = <String, List<String>>{};
        for (final c in encolador.encolados) {
          final pk = (c.payload['id'] ?? c.payload['ubicacion_id']) as String;
          (vistos['${c.entidad}/$pk'] ??= []).add(c.operacion.name);
        }
        for (final MapEntry(key: clave, value: ops) in vistos.entries) {
          expect(ops.first, 'insert', reason: '$clave empieza con su alta: $ops');
          expect(
            ops.skip(1),
            isNot(contains('insert')),
            reason: '$clave no se da de alta dos veces: $ops',
          );
        }
        for (final ub in ['ub-1', 'ub-2', 'ub-3']) {
          final jobs = encolador.encolados
              .where((c) => c.entidad == 'house_status' && c.payload['ubicacion_id'] == ub)
              .toList();
          final color = await esperado(ub);
          if (color == null) {
            if (jobs.isNotEmpty) expect(jobs.last.operacion.name, 'delete', reason: ub);
          } else {
            expect(jobs.last.operacion.name, isNot('delete'), reason: ub);
            expect(jobs.last.payload['color'], color, reason: ub);
          }
        }

        // 3. Una agenda cumplida apunta a una visita que existe y que se encoló antes.
        final posicionDeVisita = <String, int>{};
        for (final (i, c) in encolador.encolados.indexed) {
          if (c.entidad == 'visita') posicionDeVisita[c.payload['id']! as String] = i;
        }
        final visitas = {for (final v in await db.select(db.visitas).get()) v.id};
        for (final a in await db.select(db.agendas).get()) {
          if (a.estado == 'COMPLETADA') {
            expect(visitas, contains(a.visitaId), reason: '${a.id} cumplida sin visita');
            final posAgenda = encolador.encolados.lastIndexWhere(
              (c) => c.entidad == 'agenda' && c.payload['id'] == a.id,
            );
            expect(posicionDeVisita[a.visitaId]!, lessThan(posAgenda), reason: a.id);
          } else {
            expect(a.visitaId, isNull, reason: '${a.id} no cumplida con visita');
          }
        }
      });
    }
  });

  group('instantes', () {
    test('cancelar con la hora local (no UTC) guarda el mismo instante', () async {
      await repo.agendar(agendaDe('age-1'));
      final local = DateTime(2026, 10, 23, 19, 30, 5, 321);

      await repo.cancelar('age-1', ahora: local);

      final fila = (await db.select(db.agendas).get()).single;
      expect(fila.updatedAt.isUtc, isTrue);
      expect(fila.updatedAt.millisecondsSinceEpoch, local.millisecondsSinceEpoch);
      final subido = encolador.encolados.where((c) => c.entidad == 'agenda').last.payload;
      expect(DateTime.parse(subido['updated_at']! as String).isAtSameMomentAs(local), isTrue);
    });
  });

  group('hallazgos', () {
    test(
      'agendar con una ubicación alternativa que no está en el teléfono la rechaza, como '
      'hace con el vínculo (el servidor exige la FK y el job quedaría en la cola de error)',
      skip: 'QA #404: ubicacion_alt_id no se valida; una FK rota sube y el servidor la rechaza',
      () async {
        final r = await repo.agendar(
          Agenda(
            id: 'age-fk',
            espacioPersonaId: 'ep-1',
            tipo: TipoAgenda.cobranza,
            fechaProgramada: DateTime.utc(2026, 10, 25, 14),
            ubicacionAltId: 'ub-que-no-existe',
            colportorId: 'col-1',
            auditoria: auditoriaDe(),
          ),
        );
        expect(r.isLeft(), isTrue);
        expect(await db.select(db.agendas).get(), isEmpty);
      },
    );

    test(
      'registrar una visita con una jornada que no está en el teléfono la rechaza (FK de '
      'visita.jornada_id en el servidor)',
      skip: 'QA #404: jornada_id no se valida; una FK rota sube y el servidor la rechaza',
      () async {
        final r = await repo.registrarVisita(visitaDe('vis-fk', jornadaId: 'jor-que-no-existe'));
        expect(r.isLeft(), isTrue);
        expect(await db.select(db.visitas).get(), isEmpty);
      },
    );
  });
}
