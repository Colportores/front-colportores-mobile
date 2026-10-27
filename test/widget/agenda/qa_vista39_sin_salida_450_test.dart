// QA de #450, ronda «Sin salida» y «Nota entrev.» (decisiones de Cristian del 25/10; punta 893a8a0):
// el recorrido de la entrevista contra la DB real en memoria (la visita, la nota cifrada, el destino
// que se resuelve al guardar), no contra dobles. Lo que ya probó la ronda anterior (R·05 a R·07,
// aviso fijo, matriz de tamaños) está en `qa_vista39_entrevista_450_test.dart`.
//
// Capturas solo con `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas/`).
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/borrador_de_nota_de_entrevista_drift.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/destino_de_entrevista_drift.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/agenda_repository_impl.dart';
import 'package:colportores_mobile/features/agenda/domain/services/destino_de_entrevista.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/data/models/jornada_model.dart';
import 'package:colportores_mobile/features/jornada/domain/entities/jornada.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/notas_table.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/campo_falsos.dart';
import '../../helpers/entrevista_falsos.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/mapa_base_falso.dart' show overridesPestanaMapa;
import '../../helpers/qa_hu_ubi_007_212_arnes.dart' show DbFija;
import '../../helpers/qa_vista39_450_arnes.dart';

const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late EncoladorSyncEnMemoria encolador;
  late MontajeEntrevista m;

  Future<void> sembrarPersona() => db
      .into(db.personas)
      .insert(PersonasCompanion.insert(id: 'per-1', nombre: 'Pedro', createdAt: t0, updatedAt: t0));

  /// Lee o escribe en la DB fuera del reloj falso del test.
  Future<T> enDb<T>(WidgetTester tester, Future<T> Function() f) async =>
      (await tester.runAsync(f)) as T;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    encolador = EncoladorSyncEnMemoria();
    await sembrarCasa(db);
    await sembrarPersona();
    m = MontajeEntrevista();
    m.extra.add(dbLocalProvider.overrideWith(() => DbFija(db)));
    m.agendaPropia = AgendaRepositoryImpl(
      AgendaLocalDataSourceDrift(
        db,
        encolador: encolador,
        estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
      ),
    );
    m.destinoPropio = DestinoDeEntrevistaDrift(db);
    m.borradorPropio = BorradorDeNotaDeEntrevistaDrift(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// R·05 abierta de una entrevista empezada en esta sesión; escribe [nota] si viene.
  Future<Recorrido> enCurso(
    WidgetTester tester, {
    String? nota,
    Size tamano = const Size(360, 640),
    double escala = 1,
  }) async {
    final r = await montar(tester, montaje: m, tamano: tamano, escala: escala);
    await empezadaEnEstaSesion(tester, r);
    await tocar(tester, abrir);
    if (nota != null) {
      await tocar(tester, find.byKey(ClavesEntrevista.botonNota));
      await tester.enterText(find.byKey(ClavesEntrevista.campoNota), nota);
      await tester.pumpAndSettle();
    }
    return r;
  }

  String textoDelCampo(WidgetTester tester) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(ClavesEntrevista.campoNota),
          matching: find.byType(EditableText),
        ),
      )
      .controller
      .text;

  Future<void> guardar(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(ClavesEntrevista.guardarYVolver));
    await tester.tap(find.byKey(ClavesEntrevista.guardarYVolver));
    await tester.pumpAndSettle();
  }

  Future<void> finalizarYGuardar(WidgetTester tester) async {
    await tocar(tester, find.byKey(ClavesEntrevista.finalizar));
    await guardar(tester);
  }

  Future<List<VisitaFila>> visitas(WidgetTester tester) =>
      enDb(tester, () => db.select(db.visitas).get());
  Future<List<NotaFila>> notas(WidgetTester tester) =>
      enDb(tester, () => db.select(db.notas).get());

  group('Sin salida: la visita se guarda igual', () {
    testWidgets('la persona dada de baja: la visita queda de la casa, sin persona, con la nota', (
      tester,
    ) async {
      await enCurso(tester, nota: 'perro suelto, tocar timbre');
      await enDb(
        tester,
        () => (db.update(
          db.personas,
        )..where((p) => p.id.equals('per-1'))).write(PersonasCompanion(deletedAt: Value(t0))),
      );

      await finalizarYGuardar(tester);

      final v = (await visitas(tester)).single;
      expect(v.espacioId, 'esp-1');
      expect(v.espacioPersonaId, isNull, reason: 'Sin persona');
      expect(v.tipoResultado, 'ENTREVISTA');
      final n = (await notas(tester)).single;
      expect(n.targetType, TipoObjetivoNota.visita);
      expect(n.targetId, v.id);
      expect(n.texto, 'perro suelto, tocar timbre');
      expect(m.almacen.guardadas, isEmpty, reason: 'la entrevista se soltó');
      expect(find.text(TextosEntrevista.guardada('Grecia 3307')), findsOneWidget);
    });

    testWidgets('el vínculo dado de baja: sin persona, y la jornada de la hoja sigue libre', (
      tester,
    ) async {
      await enCurso(tester);
      await enDb(
        tester,
        () => (db.update(
          db.espacioPersonas,
        )..where((v) => v.id.equals('ep-1'))).write(EspacioPersonasCompanion(deletedAt: Value(t0))),
      );

      await finalizarYGuardar(tester);

      expect((await visitas(tester)).single.espacioPersonaId, isNull);
      expect(find.byKey(ClavesEntrevista.guardarYVolver), findsNothing);
    });

    testWidgets('la casa se fundió con otra: la visita va a la que quedó, con su persona', (
      tester,
    ) async {
      await enCurso(tester, nota: 'tocar dos veces');
      await enDb(tester, () async {
        await sembrarEspacio(db, id: 'esp-que-quedo');
        await (db.update(
          db.espacios,
        )..where((e) => e.id.equals('esp-1'))).write(EspaciosCompanion(deletedAt: Value(t0)));
        await (db.update(db.espacioPersonas)..where((v) => v.id.equals('ep-1'))).write(
          const EspacioPersonasCompanion(espacioId: Value('esp-que-quedo')),
        );
      });

      await finalizarYGuardar(tester);

      final v = (await visitas(tester)).single;
      expect(v.espacioId, 'esp-que-quedo');
      expect(v.espacioPersonaId, 'ep-1');
      expect((await notas(tester)).single.targetId, v.id);
    });

    testWidgets(
      'la casa se fundió y la persona también se dio de baja: casa vigente, sin persona',
      (tester) async {
        await enCurso(tester);
        await enDb(tester, () async {
          await sembrarEspacio(db, id: 'esp-que-quedo');
          await (db.update(
            db.espacios,
          )..where((e) => e.id.equals('esp-1'))).write(EspaciosCompanion(deletedAt: Value(t0)));
          await (db.update(db.espacioPersonas)..where((v) => v.id.equals('ep-1'))).write(
            EspacioPersonasCompanion(espacioId: const Value('esp-que-quedo'), deletedAt: Value(t0)),
          );
        });

        await finalizarYGuardar(tester);

        final v = (await visitas(tester)).single;
        expect(v.espacioId, 'esp-que-quedo');
        expect(v.espacioPersonaId, isNull);
      },
    );

    testWidgets('lo que se guarda no sube la nota: ni una operación de sync para `nota`', (
      tester,
    ) async {
      await enCurso(tester, nota: 'dato personal: la señora vive sola');

      await finalizarYGuardar(tester);

      expect(encolador.encolados.map((c) => c.entidad), isNot(contains('nota')));
      for (final c in encolador.encolados) {
        expect(
          c.payload.values.map((v) => '$v'),
          isNot(contains(contains('dato personal'))),
          reason: 'el texto de la nota no viaja en el payload de ${c.entidad}',
        );
      }
    });
  });

  group('Sin salida: ni la casa ni el depto siguen en el teléfono', () {
    Future<void> casaFuera(WidgetTester tester) => enDb(
      tester,
      () => (db.update(
        db.espacios,
      )..where((e) => e.id.equals('esp-1'))).write(EspaciosCompanion(deletedAt: Value(t0))),
    );

    testWidgets('la entrevista se suelta con su nota, se avisa y no queda ninguna visita', (
      tester,
    ) async {
      final r = await enCurso(tester, nota: 'esto no se debe quedar huérfano');
      expect((await notas(tester)), hasLength(1), reason: 'el borrador está en la base');
      await casaFuera(tester);

      await finalizarYGuardar(tester);

      expect(await visitas(tester), isEmpty);
      expect(await notas(tester), isEmpty, reason: 'el borrador se borró con la entrevista');
      expect(m.almacen.guardadas, isEmpty);
      expect(find.text(TextosEntrevista.sinLugar), findsOneWidget);
      expect(find.text('Terminó la entrevista'), findsNothing, reason: 'la hoja se cerró');
      expect(r.devolvio, isTrue);
      expect(find.byKey(ClavesEntrevista.avisoFijo), findsNothing, reason: 'el aviso fijo se fue');
      // El aviso es una región viva: el lector lo anuncia sin que haya que buscarlo.
      final semantica = tester.getSemantics(find.text(TextosEntrevista.sinLugar));
      expect(semantica.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    });

    testWidgets('después de soltarla, «Finalizar» ya no encuentra entrevista (no hay trampa)', (
      tester,
    ) async {
      await enCurso(tester);
      await casaFuera(tester);
      await finalizarYGuardar(tester);

      await tocar(tester, terminar);

      expect(find.text('Terminó la entrevista'), findsNothing);
      expect(await visitas(tester), isEmpty);
    });

    testWidgets('un doble toque en «No, guardar…» no repite el aviso ni descarta dos veces', (
      tester,
    ) async {
      await enCurso(tester);
      await casaFuera(tester);
      await tocar(tester, find.byKey(ClavesEntrevista.finalizar));
      await tester.ensureVisible(find.byKey(ClavesEntrevista.guardarYVolver));

      await tester.tap(find.byKey(ClavesEntrevista.guardarYVolver));
      await tester.tap(find.byKey(ClavesEntrevista.guardarYVolver), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text(TextosEntrevista.sinLugar), findsOneWidget);
      expect(await visitas(tester), isEmpty);
    });

    testWidgets('si el almacén falla al soltar, el aviso dice qué hacer y la entrevista sigue', (
      tester,
    ) async {
      await enCurso(tester, nota: 'sigo aquí');
      await casaFuera(tester);
      m.rota.fallaAlBorrar = true;
      await tocar(tester, find.byKey(ClavesEntrevista.finalizar));
      await guardar(tester);

      expect(find.text(TextosEntrevista.noPudimosGuardar), findsOneWidget);
      expect(m.almacen.guardadas, isNotEmpty, reason: 'no se perdió la entrevista');
      expect((await notas(tester)).single.texto, 'sigo aquí');
      // El botón vuelve a estar libre y el reintento termina de soltarla.
      m.rota.fallaAlBorrar = false;
      await guardar(tester);

      expect(find.text(TextosEntrevista.sinLugar), findsOneWidget);
      expect(m.almacen.guardadas, isEmpty);
      expect(await notas(tester), isEmpty);
    });

    testWidgets(
      'cerrar R·06 mientras se suelta la entrevista: igual se avisa que no se guardó',
      (tester) async {
        // Hoy la hoja devuelve `null` al cerrarse y el aviso nunca sale: la entrevista desaparece
        // del mapa sin que la colportora sepa que su visita no quedó.
        final lento = _DestinoLento();
        m.destinoPropio = lento;
        await enCurso(tester, nota: 'no se pierde sin avisar');
        await tocar(tester, find.byKey(ClavesEntrevista.finalizar));
        await tester.ensureVisible(find.byKey(ClavesEntrevista.guardarYVolver));
        await tester.tap(find.byKey(ClavesEntrevista.guardarYVolver));
        await tester.pump();

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        lento.compuerta.complete();
        await tester.pumpAndSettle();

        expect(m.almacen.guardadas, isEmpty, reason: 'la entrevista se soltó');
        expect(find.text(TextosEntrevista.sinLugar), findsOneWidget);
      },
      // skip: QA #450 — cerrar la hoja con el guardado en vuelo y la casa ya fuera suelta la entrevista sin avisar.
      skip: !_hallazgos,
    );

    testWidgets('R·06 de una persona que ya no está: el título y el resumen no quedan con huecos', (
      tester,
    ) async {
      m.rotulo = (direccion: 'Grecia 3307', persona: '');
      await enCurso(tester, tamano: const Size(360, 640), escala: 2);
      await tocar(tester, find.byKey(ClavesEntrevista.finalizar));

      expect(tester.takeException(), isNull);
      sinTextoCortado(tester);
      expect(find.textContaining('null'), findsNothing);
      await capturar(tester, 'r06_sin_persona_360x640_x2');
    });

    testWidgets(
      'R·07 (sin inicio) con la casa fuera: el error dice qué pasó y deja salir sin «cerró»',
      (tester) async {
        // R·07 no tiene entrevista que soltar: «se cerró sin guardar» no describe lo que ve.
        m.ultimaVisita.fecha = DateTime(2026, 10, 23, 14, 10);
        await montar(tester, montaje: m);
        await casaFuera(tester);
        await tocar(tester, sinInicio);

        await guardar(tester);

        expect(find.text('Terminó la entrevista'), findsOneWidget, reason: 'la hoja sigue abierta');
        expect(find.textContaining('se cerró sin guardar'), findsNothing);
      },
      skip: !_hallazgos,
    );
  });

  group('Nota entrev.: cifrada en el teléfono, junto a la entrevista', () {
    testWidgets('cada cambio de la nota queda en la base mientras la entrevista sigue en curso', (
      tester,
    ) async {
      await enCurso(tester, nota: 'perro');
      expect((await notas(tester)).single.texto, 'perro');

      await tester.enterText(find.byKey(ClavesEntrevista.campoNota), 'perro suelto');
      await tester.pumpAndSettle();
      expect((await notas(tester)).single.texto, 'perro suelto');

      await tester.enterText(find.byKey(ClavesEntrevista.campoNota), '   ');
      await tester.pumpAndSettle();
      expect(await notas(tester), isEmpty, reason: 'en blanco no deja una nota vacía');
    });

    testWidgets('escribir de corrido y finalizar: manda la última versión, una sola fila', (
      tester,
    ) async {
      await enCurso(tester, nota: 'a');
      for (final t in ['ab', 'abc', 'abcd con emoji 🐕 y «comillas»', 'última']) {
        await tester.enterText(find.byKey(ClavesEntrevista.campoNota), t);
        await tester.pump();
      }

      await finalizarYGuardar(tester);

      expect((await notas(tester)).single.texto, 'última');
    });

    testWidgets('se cierra la app con la nota escrita: al volver está, y viaja con la visita', (
      tester,
    ) async {
      await enCurso(tester, nota: 'volver con la esposa después de las seis');
      // La app se cierra: se desmonta todo y se arma de cero sobre el mismo almacén y la misma base.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      final r = await montar(tester, montaje: m);
      expect(m.almacen.guardadas, isNotEmpty);

      await tocar(tester, abrir);
      // La nota ya escrita aparece abierta, sin tocar «✎ Nota de la visita».
      if (find.byKey(ClavesEntrevista.campoNota).evaluate().isEmpty) {
        await tocar(tester, find.byKey(ClavesEntrevista.botonNota));
      }
      expect(
        textoDelCampo(tester),
        'volver con la esposa después de las seis',
        reason: 'la nota recuperada de la base aparece en el campo',
      );

      // Como la app se cerró, la salida no se inventa: se pide.
      await tocar(tester, find.byKey(ClavesEntrevista.finalizar));
      expect(find.text(TextosEntrevista.pedirSalida), findsOneWidget);
      await tester.tap(find.byKey(ClavesEntrevista.filaSalida));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hoja_hora_menos')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('hoja_hora_usar')));
      await tester.pumpAndSettle();
      await guardar(tester);

      expect(r.devolvio, isTrue);
      final n = (await notas(tester)).single;
      expect(n.texto, 'volver con la esposa después de las seis');
      expect(n.targetId, (await visitas(tester)).single.id);
    });

    testWidgets(
      'si la base no escribe la nota, se avisa solo en el log y lo tipeado no se pierde',
      (tester) async {
        // Una base que falla al escribir: la nota sigue en el campo y viaja con la visita.
        m.borradorPropio = BorradorFalso()..fallaAlGuardar = true;
        await enCurso(tester, nota: 'sigue en la pantalla');

        expect(textoDelCampo(tester), 'sigue en la pantalla');
        await finalizarYGuardar(tester);

        expect((await notas(tester)).single.texto, 'sigue en la pantalla');
      },
    );
  });

  group('Finalizar la jornada con la casa de la entrevista ya fuera del teléfono', () {
    final sesion = Sesion(
      usuarioId: 'col-1',
      email: 'lucia.silva@correo.com',
      accessToken: 'token',
      expiraEn: DateTime.utc(2030),
    );

    Future<JornadaLocalDataSourceEnMemoria> montarJornada(
      WidgetTester tester, {
      double escala = 1,
      Size tamano = const Size(390, 844),
    }) async {
      final inicio = DateTime(2026, 10, 23, 13, 15);
      final jornadas = JornadaLocalDataSourceEnMemoria(
        iniciales: [
          JornadaModel.fromEntity(
            Jornada(
              id: 'jor-1',
              colportorId: sesion.usuarioId,
              inicio: inicio,
              auditoria: Auditoria(
                createdAt: inicio,
                updatedAt: inicio,
                createdBy: sesion.usuarioId,
              ),
            ),
          ),
        ],
      );
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            jornadaLocalDataSourceProvider.overrideWithValue(jornadas),
            disparadorBackupProvider.overrideWithValue(_BackupFalso()),
            relojJornadaProvider.overrideWithValue(() => ahoraEntrevista),
            ...overridesPestanaMapa(),
            ...m.overrides,
          ],
          child: MaterialApp(
            theme: temaClaro(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(escala), alwaysUse24HourFormat: true),
              child: child!,
            ),
            home: InicioPage(sesion: sesion),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return jornadas;
    }

    /// Desmonta la pantalla y cierra la base fuera del reloj falso: si no, quedan los timers de las
    /// consultas en vivo de Drift.
    Future<void> desmontar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(db.close);
    }

    Future<void> elegirSalidaYGuardar(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(ClavesEntrevista.filaSalida));
      await tester.tap(find.byKey(ClavesEntrevista.filaSalida));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hoja_hora_menos')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('hoja_hora_usar')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(ClavesEntrevista.guardarYVolver));
      await tester.tap(find.byKey(ClavesEntrevista.guardarYVolver));
      await tester.pumpAndSettle();
    }

    testWidgets('se le pide la salida, se avisa que no se guardó y la jornada se cierra igual', (
      tester,
    ) async {
      await m.almacen.guardar(entrevistaDePrueba());
      await enDb(
        tester,
        () => (db.update(
          db.espacios,
        )..where((e) => e.id.equals('esp-1'))).write(EspaciosCompanion(deletedAt: Value(t0))),
      );
      final jornadas = await montarJornada(tester);

      await tester.ensureVisible(find.byKey(const Key('jornada_finalizar')));
      await tester.tap(find.byKey(const Key('jornada_finalizar')));
      await tester.pumpAndSettle();
      expect(find.text(TextosEntrevista.pedirSalida), findsOneWidget);
      await elegirSalidaYGuardar(tester);

      expect(await visitas(tester), isEmpty);
      expect(m.almacen.guardadas, isEmpty);
      expect(jornadas.jornadas.any((j) => j.fin == null), isFalse, reason: 'jornada cerrada');
      expect(tester.takeException(), isNull);
      await desmontar(tester);
    });

    testWidgets('con la persona dada de baja, la visita sin persona queda y la jornada se cierra', (
      tester,
    ) async {
      await m.almacen.guardar(entrevistaDePrueba());
      await enDb(
        tester,
        () => (db.update(
          db.personas,
        )..where((p) => p.id.equals('per-1'))).write(PersonasCompanion(deletedAt: Value(t0))),
      );
      final jornadas = await montarJornada(tester, escala: 2, tamano: const Size(360, 640));

      await tester.ensureVisible(find.byKey(const Key('jornada_finalizar')));
      await tester.tap(find.byKey(const Key('jornada_finalizar')));
      await tester.pumpAndSettle();
      await elegirSalidaYGuardar(tester);

      final v = (await visitas(tester)).single;
      expect(v.espacioPersonaId, isNull);
      expect(jornadas.jornadas.any((j) => j.fin == null), isFalse);
      expect(tester.takeException(), isNull);
      await desmontar(tester);
    });
  });

  group('Aviso «Sin salida» a cada tamaño', () {
    for (final tamano in tamanos39) {
      for (final escala in escalas39) {
        final celda = '${tamano.width.toInt()}x${tamano.height.toInt()} x${escala.toInt()}';
        testWidgets('el aviso de la casa que ya no está se lee entero y es región viva ($celda)', (
          tester,
        ) async {
          await enCurso(tester, tamano: tamano, escala: escala);
          await enDb(
            tester,
            () => (db.update(
              db.espacios,
            )..where((e) => e.id.equals('esp-1'))).write(EspaciosCompanion(deletedAt: Value(t0))),
          );

          await finalizarYGuardar(tester);

          expect(tester.takeException(), isNull);
          final aviso = find.text(TextosEntrevista.sinLugar);
          expect(aviso, findsOneWidget);
          sinTextoCortado(tester);
          final caja = tester.getRect(find.ancestor(of: aviso, matching: find.byType(SnackBar)));
          expect(caja.left, greaterThanOrEqualTo(0));
          expect(caja.right, lessThanOrEqualTo(tamano.width));
          expect(caja.top, greaterThanOrEqualTo(0));
          expect(caja.bottom, lessThanOrEqualTo(tamano.height));
          await capturar(
            tester,
            'sinLugar_${tamano.width.toInt()}x${tamano.height.toInt()}_x${escala.toInt()}',
          );
        });
      }
    }
  });
}

/// Un destino que espera a que el test lo suelte y responde que ya no hay dónde guardar.
final class _DestinoLento implements ResolverDestinoDeEntrevista {
  final compuerta = Completer<void>();

  @override
  Future<DestinoDeEntrevista?> resolver({
    required String espacioId,
    required String espacioPersonaId,
  }) async {
    await compuerta.future;
    return null;
  }
}

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}
