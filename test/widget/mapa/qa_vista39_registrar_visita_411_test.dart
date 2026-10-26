// QA de «Registrar visita: ¿qué pasó?» y del aviso «Guardado» (vista 39, C·06 y R·01, HU-VIS-005, #411,
// PR #474). Lo que no prueban los tests del PR:
//
// - la matriz de estados × 360x640 / 412x915 × texto 1,0 / 2,0 con las fuentes reales (sin desborde, nada
//   fuera de la pantalla) y sus capturas (con `--dart-define=QA_CAPTURAS=true`);
// - los tres escenarios de la HU de punta a punta con la base real (Drift en memoria): una persona toca
//   y la casa, la visita y la agenda quedan como la HU promete, y «Deshacer» lo devuelve;
// - el enganche de producción (`main.dart` abre el flujo con el contexto del propio `Navigator`);
// - casos límite de acciones superpuestas, de la hoja ocupada y de lo que oye el lector de pantalla.
//
// Las guías de accesibilidad van aparte (`qa_vista39_registrar_visita_411_guias_test.dart`).
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/agenda_repository_impl.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/registrar_resultado_visita_use_case.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:colportores_mobile/features/mapa/presentation/flujo_registrar_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_repositorio_falso.dart';
import '../../helpers/campo_falsos.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_hojas_teclado_324_arnes.dart' show cargarTipografias;
import '../../helpers/qa_vista39_411_arnes.dart';
import 'personas_arnes.dart';
import 'registrar_visita_arnes.dart';

const _guardadoNoContesto = 'Guardado. Grecia 3307 quedó como «No contestó».';
const _guardadoRechazo = 'Guardado. Grecia 3307 quedó como «Rechazo».';

Finder get _deshacer => find.text('Deshacer');

/// Corre también los tests que documentan un hallazgo de QA (`skip` mientras no se arregle).
const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

/// Cuántos píxeles puede sobresalir un texto de la pantalla por redondeos.
const _tolerancia = 0.6;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(cargarTipografias);

  // ---------------------------------------------------------------------------------------------
  // Matriz de estados × tamaños × escalas, con fuentes reales: sin desborde y nada fuera de pantalla.
  // ---------------------------------------------------------------------------------------------
  group('matriz de estados con fuentes reales', () {
    for (final tamano in [t360x640, t412x915]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in Estado411.values) {
          testWidgets(
            '${estado.name} · ${sufijo411(tamano, escala)}: sin desborde y ningún texto se sale '
            'de la pantalla',
            (tester) async {
              await llegarA411(tester, estado, tamano: tamano, escala: escala);
              await tester.pump(const Duration(milliseconds: 400));

              expect(tester.takeException(), isNull, reason: 'overflow');
              final textos = find.byType(Text);
              for (var i = 0; i < textos.evaluate().length; i++) {
                final r = tester.getRect(textos.at(i));
                expect(
                  r.left,
                  greaterThanOrEqualTo(-_tolerancia),
                  reason: 'texto ${i + 1} sale por la izquierda: $r',
                );
                expect(
                  r.right,
                  lessThanOrEqualTo(tamano.width + _tolerancia),
                  reason: 'texto ${i + 1} sale por la derecha: $r',
                );
              }
              if (find.byType(SnackBar).evaluate().isNotEmpty) {
                final aviso = tester.getRect(find.byType(SnackBar));
                expect(aviso.bottom, lessThanOrEqualTo(tamano.height + _tolerancia));
                expect(aviso.top, greaterThanOrEqualTo(0));
                if (find.text('Deshacer').evaluate().isNotEmpty) {
                  final accion = tester.getRect(find.text('Deshacer'));
                  expect(accion.right, lessThanOrEqualTo(tamano.width + _tolerancia));
                  expect(accion.bottom, lessThanOrEqualTo(tamano.height + _tolerancia));
                }
              }
              await capturar411(tester, '${estado.name}_${sufijo411(tamano, escala)}');
            },
          );
        }
      }
    }

    testWidgets('c06Cinco · 320x568 a 2,0 y 3,0: la hoja se desplaza, todo se alcanza y «Cancelar» '
        'queda entero a la vista', (tester) async {
      for (final escala in [2.0, 3.0]) {
        await llegarA411(tester, Estado411.c06Cinco, tamano: t320x568, escala: escala);
        expect(tester.takeException(), isNull);
        for (final o in OpcionQuePaso.values) {
          await tester.ensureVisible(renglon(o));
          await tester.pump();
          final r = tester.getRect(renglon(o));
          expect(r.height, greaterThanOrEqualTo(56), reason: '${o.name} a $escala×');
          expect(r.width, greaterThanOrEqualTo(48));
        }
        await tester.ensureVisible(find.byKey(ClavesQuePaso.cancelar));
        await tester.pump();
        final c = tester.getRect(find.byKey(ClavesQuePaso.cancelar));
        expect(c.bottom, lessThanOrEqualTo(568 + _tolerancia));
        expect(c.height, greaterThanOrEqualTo(48));
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });

  // ---------------------------------------------------------------------------------------------
  // Texto literal del canvas y orden.
  // ---------------------------------------------------------------------------------------------
  group('C·06 · el canvas letra por letra', () {
    testWidgets(
      'dado las cinco opciones, cuando se abre, salen en el orden del canvas con sus ayudas '
      'literales',
      (tester) async {
        await llegarA411(tester, Estado411.c06Cinco);

        final orden = [for (final o in OpcionQuePaso.values) tester.getTopLeft(renglon(o)).dy];
        expect(
          [...orden]..sort(),
          orden,
          reason: 'No contestó, Rechazo, Programar, Dada, Cobranza',
        );
        expect(OpcionQuePaso.values.map((o) => o.name).toList(), [
          'noContesto',
          'rechazo',
          'programarEntrevista',
          'entrevistaDada',
          'cobranza',
        ]);
        for (final texto in [
          '¿Qué pasó?',
          'Grecia 3307',
          'No contestó',
          'Rechazo',
          'Programar entrevista',
          'Entrevista dada',
          'Cobranza',
          'Guarda y vuelve al mapa',
          'Elegís día y franja',
          'Empieza a contar el tiempo',
          'Pedro Gómez debe \$ 1.200',
          'Cancelar',
        ]) {
          expect(find.text(texto), findsWidgets, reason: texto);
        }
      },
    );

    testWidgets(
      'dado la hoja abierta, cuando se mira el árbol de semántica, el título es un encabezado y '
      'cada renglón es un botón con título y ayuda',
      (tester) async {
        final handle = tester.ensureSemantics();
        await llegarA411(tester, Estado411.c06Cinco);

        expect(
          tester.getSemantics(find.text('¿Qué pasó?')),
          isSemantics(label: '¿Qué pasó?', isHeader: true),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('No contestó. Guarda y vuelve al mapa')),
          isSemantics(
            label: 'No contestó. Guarda y vuelve al mapa',
            isButton: true,
            hasTapAction: true,
            hasEnabledState: true,
            isEnabled: true,
          ),
        );
        handle.dispose();
      },
    );
  });

  // ---------------------------------------------------------------------------------------------
  // Acciones superpuestas y hoja ocupada.
  // ---------------------------------------------------------------------------------------------
  group('hoja ocupada y acciones superpuestas', () {
    testWidgets(
      'dado «No contestó» guardando, cuando se toca «Rechazo» enseguida, solo se guarda una '
      'visita y es la primera',
      (tester) async {
        final compuerta = Completer<void>();
        addTearDown(() {
          if (!compuerta.isCompleted) compuerta.complete();
        });
        final repo = AgendaRepositorioFalso()..compuerta = compuerta;
        final a = await montarQuePaso(tester, repo: repo);

        await elegir(tester, OpcionQuePaso.noContesto);
        await tester.tap(renglon(OpcionQuePaso.rechazo), warnIfMissed: false);
        await asentar(tester);
        compuerta.complete();
        await asentar(tester);

        expect(a.repo.recibidas, hasLength(1));
        expect(a.repo.recibidas.single.visita.tipoResultado, TipoResultadoVisita.noContesto);
        expect(find.text(_guardadoNoContesto), findsOneWidget);
        expect(find.text(_guardadoRechazo), findsNothing);
        expect(a.resultados, [true]);
      },
    );

    testWidgets(
      'dado un guardado en curso, cuando se toca afuera de la hoja o se aprieta el atrás del '
      'sistema, la hoja no se cierra y la visita no se pierde',
      (tester) async {
        final compuerta = Completer<void>();
        addTearDown(() {
          if (!compuerta.isCompleted) compuerta.complete();
        });
        final repo = AgendaRepositorioFalso()..compuerta = compuerta;
        final a = await montarQuePaso(tester, repo: repo);
        await elegir(tester, OpcionQuePaso.rechazo);
        expect(find.byKey(ClavesQuePaso.guardando), findsOneWidget);

        await tester.tapAt(const Offset(12, 12));
        await asentar(tester);
        expect(find.byKey(ClavesQuePaso.hoja), findsOneWidget, reason: 'toque en el fondo');
        await tester.binding.handlePopRoute();
        await asentar(tester);
        expect(find.byKey(ClavesQuePaso.hoja), findsOneWidget, reason: 'atrás del sistema');
        expect(a.resultados, isEmpty);

        compuerta.complete();
        await asentar(tester);

        expect(find.byKey(ClavesQuePaso.hoja), findsNothing);
        expect(a.resultados, [true]);
        expect(find.text(_guardadoRechazo), findsOneWidget);
        expect(a.repo.recibidas, hasLength(1));
      },
    );

    testWidgets(
      'dado un guardado en curso, cuando el lector mira los otros renglones, están deshabilitados '
      'y el que corre dice «Guardando…»',
      (tester) async {
        final handle = tester.ensureSemantics();
        final compuerta = Completer<void>();
        addTearDown(() {
          if (!compuerta.isCompleted) compuerta.complete();
        });
        final repo = AgendaRepositorioFalso()..compuerta = compuerta;
        await montarQuePaso(tester, repo: repo);
        await elegir(tester, OpcionQuePaso.noContesto);

        expect(
          tester.getSemantics(find.bySemanticsLabel('Rechazo. Guarda y vuelve al mapa')),
          isSemantics(
            label: 'Rechazo. Guarda y vuelve al mapa',
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
          ),
        );
        expect(find.bySemanticsLabel('No contestó. Guardando…'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets(
      'dado una falla al guardar, cuando aparece el aviso rojo, el lector lo anuncia como región '
      'viva',
      (tester) async {
        final handle = tester.ensureSemantics();
        await llegarA411(tester, Estado411.c06Falla);

        final nodo = tester.getSemantics(find.byKey(ClavesQuePaso.falla));
        expect(
          nodo,
          isSemantics(label: 'No pudimos guardar la visita. Probá de nuevo.', isLiveRegion: true),
        );
        handle.dispose();
      },
    );

    testWidgets(
      'dado una falla y volver a intentar con otra opción, cuando sale bien, el aviso rojo se '
      'va y la casa queda con el resultado nuevo',
      (tester) async {
        final repo = AgendaRepositorioFalso()
          ..resultados.add(const FailureInesperado(causa: 'StateError'));
        final a = await montarQuePaso(tester, repo: repo);

        await elegir(tester, OpcionQuePaso.noContesto);
        expect(find.byKey(ClavesQuePaso.falla), findsOneWidget);
        await elegir(tester, OpcionQuePaso.rechazo);

        expect(find.byKey(ClavesQuePaso.falla), findsNothing);
        expect(find.byKey(ClavesQuePaso.hoja), findsNothing);
        expect(a.repo.recibidas.last.visita.tipoResultado, TipoResultadoVisita.rechazo);
        expect(find.text(_guardadoRechazo), findsOneWidget);
      },
    );

    testWidgets(
      'dado dos aperturas seguidas de «¿Qué pasó?», cuando se guarda en cada una, las visitas '
      'llevan ids distintos y ninguna pisa a la otra',
      (tester) async {
        final a = await montarQuePaso(tester);
        await elegir(tester, OpcionQuePaso.noContesto);
        await tester.pump(const Duration(seconds: 9));
        await abrirQuePaso(tester);
        await elegir(tester, OpcionQuePaso.noContesto);

        expect(a.resultados, [true, true]);
        final ids = a.repo.recibidas.map((r) => r.visita.id).toList();
        expect(ids, hasLength(2));
        expect(ids.toSet(), hasLength(2), reason: 'una visita por apertura');
      },
    );
  });

  // ---------------------------------------------------------------------------------------------
  // El aviso de error tiene que verse sin que la persona deba adivinar que hay que desplazar.
  // ---------------------------------------------------------------------------------------------
  group('el aviso de falla queda a la vista', () {
    // `hallazgo`: los casos que hoy fallan (hallazgo de QA #411). Se corren con
    // `--dart-define=QA_HALLAZGOS=true`; el implementador saca el `skip` al arreglarlo.
    for (final caso in [
      (cinco: false, tamano: t320x568, escala: 2.0, hallazgo: true),
      (cinco: false, tamano: t320x568, escala: 3.0, hallazgo: true),
      (cinco: true, tamano: t360x640, escala: 1.0, hallazgo: false),
      (cinco: true, tamano: t360x640, escala: 1.3, hallazgo: false),
      (cinco: true, tamano: t360x640, escala: 1.5, hallazgo: true),
      (cinco: true, tamano: t360x640, escala: 2.0, hallazgo: true),
      (cinco: true, tamano: t412x915, escala: 2.0, hallazgo: true),
    ]) {
      testWidgets(
        '${caso.cinco ? 'cinco opciones' : 'dos opciones'} · ${sufijo411(caso.tamano, caso.escala)}: '
        'dado una falla al tocar «No contestó», cuando la hoja la muestra, el aviso rojo queda '
        'entero dentro de la pantalla sin desplazar',
        // skip: QA #411 — con texto grande el aviso rojo queda debajo de los renglones y de la vista
        // (no hay desplazamiento hacia él): la persona no se entera de que falló.
        skip: caso.hallazgo && !_verHallazgos,
        (tester) async {
          final repo = AgendaRepositorioFalso()
            ..resultados.add(const FailureInesperado(causa: 'StateError'));
          await montarQuePaso(
            tester,
            repo: repo,
            personas: caso.cinco ? [clienteDePersonas('pedro', 'Pedro', apellido: 'Gómez')] : [],
            saldos: caso.cinco ? {'pedro': 120000} : {},
            programar: caso.cinco,
            entrevistaDada: caso.cinco,
            cobrar: caso.cinco,
            tamano: caso.tamano,
            escala: caso.escala,
          );
          await elegir(tester, OpcionQuePaso.noContesto);
          await tester.pump(const Duration(milliseconds: 400));

          final aviso = find.byKey(ClavesQuePaso.falla);
          expect(aviso, findsOneWidget, reason: 'la falla se dibuja');
          final r = tester.getRect(aviso);
          await capturar411(
            tester,
            'falla_fuera_${caso.cinco ? 'cinco' : 'dos'}_${sufijo411(caso.tamano, caso.escala)}',
          );
          expect(
            r.top >= 0 && r.bottom <= caso.tamano.height + _tolerancia,
            isTrue,
            reason:
                'el aviso rojo quedó en $r de una pantalla de ${caso.tamano}: hay que desplazar '
                'para verlo',
          );
        },
      );
    }
  });

  // ---------------------------------------------------------------------------------------------
  // Privacidad.
  // ---------------------------------------------------------------------------------------------
  group('privacidad', () {
    test(
      'dado una nota en los parámetros, cuando se hace toString, no sale la nota ni el colportor',
      () {
        const params = RegistrarResultadoVisitaParams(
          ids: IdsResultadoVisita(visita: 'v-1', nota: 'n-1'),
          espacioId: 'esp-1',
          colportorId: 'col-secreto',
          resultado: TipoResultadoVisita.noContesto,
          nota: 'el perro es bravo y vive Pedro Gómez',
        );
        final texto = '$params';
        expect(texto, isNot(contains('perro')));
        expect(texto, isNot(contains('Pedro')));
        expect(texto, isNot(contains('col-secreto')));
      },
    );
  });

  // ---------------------------------------------------------------------------------------------
  // De punta a punta con la base real: los escenarios de la HU.
  // ---------------------------------------------------------------------------------------------
  group('HU-VIS-005 con la base real', () {
    late AppDatabase db;
    late EncoladorSyncEnMemoria encolador;
    late AgendaLocalDataSourceDrift local;
    final navegador = GlobalKey<NavigatorState>();
    final resultados = <bool>[];

    Future<T> enBase<T>(WidgetTester tester, Future<T> Function() f) async =>
        (await tester.runAsync(f)) as T;

    /// Deja correr la base real y el reloj falso.
    Future<void> esperar(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// Monta la app con el repositorio de la agenda sobre Drift en memoria y abre «¿Qué pasó?» como
    /// lo hace `main.dart`: con el contexto del propio `Navigator`.
    Future<void> montarReal(
      WidgetTester tester, {
      Future<void> Function()? sembrar,
      Size tamano = t412x915,
    }) async {
      resultados.clear();
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      encolador = EncoladorSyncEnMemoria();
      final updater = HouseStatusUpdaterDrift(db, encolador: encolador);
      var n = 0;
      local = AgendaLocalDataSourceDrift(
        db,
        encolador: encolador,
        estadoDeLasCasas: updater,
        generarId: () => 'age-esp-${++n}',
      );
      await enBase(tester, () async {
        await sembrarCasa(db);
        await sembrar?.call();
        encolador.encolados.clear();
      });
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var v = 0;
      var minutos = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            agendaRepositoryProvider.overrideWithValue(AgendaRepositoryImpl(local)),
            generadorIdVisitaProvider.overrideWithValue(() => 'vis-${++v}'),
            relojVisitaProvider.overrideWithValue(
              () => DateTime.utc(2026, 10, 25, 15).add(Duration(minutes: minutos++)),
            ),
            personaRepositoryProvider.overrideWithValue(PersonaRepositorioFalso()),
            espacioRepositoryProvider.overrideWithValue(
              EspacioRepositorioParaPersonas(casaGrecia()),
            ),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            navigatorKey: navegador,
            home: Scaffold(
              body: Center(
                child: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      resultados.add(
                        await FlujoRegistrarVisita.abrir(navegador.currentContext!, (
                          ubicacionId: 'ub-1',
                          espacioId: 'esp-1',
                        ), colportorId: 'col-1'),
                      );
                    },
                    child: const Text('registrar visita'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('registrar visita'));
      await esperar(tester);
    }

    Future<List<VisitaFila>> visitas(WidgetTester tester) =>
        enBase(tester, () => db.select(db.visitas).get());
    Future<List<AgendaFila>> agendas(WidgetTester tester) =>
        enBase(tester, () => db.select(db.agendas).get());
    Future<List<HouseStatusFila>> casas(WidgetTester tester) =>
        enBase(tester, () => db.select(db.houseStatuses).get());

    /// Desmonta y cierra: Drift deja un timer al cancelar un stream.
    Future<void> cerrar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(db.close);
    }

    testWidgets(
      'Escenario: Registrar NO_CONTESTO. Dado que toqué timbre y no contestaron y la casa tenía '
      'una agenda, cuando registro NO_CONTESTO, entonces house_status = no_answer (gris) y la '
      'agenda pasa a NO_CUMPLIDA',
      (tester) async {
        await montarReal(
          tester,
          sembrar: () async {
            await local.agendar(agendaDe('age-1'));
          },
        );
        expect(await casas(tester), hasLength(1));
        expect((await casas(tester)).single.color, 'ENTREVISTA_PROGRAMADA');

        await tester.tap(renglon(OpcionQuePaso.noContesto));
        await esperar(tester);

        expect(resultados, [true]);
        final visita = (await visitas(tester)).single;
        expect(visita.tipoResultado, 'NO_CONTESTO');
        expect(visita.espacioPersonaId, isNull, reason: 'decisión «Sin persona»');
        final agenda = (await agendas(tester)).single;
        expect(agenda.id, 'age-1');
        expect(agenda.estado, 'NO_CUMPLIDA');
        expect(agenda.visitaId, visita.id);
        expect((await casas(tester)).single.color, 'SIN_CONTESTAR');
        expect(find.text(_guardadoNoContesto), findsOneWidget);
        await cerrar(tester);
      },
    );

    testWidgets(
      'Escenario: Registrar RECHAZO. Dado que el cliente rechazó, cuando registro RECHAZO, '
      'entonces house_status = rejected (rojo)',
      (tester) async {
        await montarReal(tester);

        await tester.tap(renglon(OpcionQuePaso.rechazo));
        await esperar(tester);

        expect((await visitas(tester)).single.tipoResultado, 'RECHAZO');
        expect((await casas(tester)).single.color, 'RECHAZO');
        expect(find.text(_guardadoRechazo), findsOneWidget);
        await cerrar(tester);
      },
    );

    testWidgets(
      'Escenario: Edge, registrar resultado sin agenda previa (visita espontánea). Dado que paso '
      'por una ubicación sin agenda, cuando registro resultado, entonces se crea agenda '
      'backdated (CUMPLIDA directamente) + resultado',
      (tester) async {
        await montarReal(tester);
        expect(await agendas(tester), isEmpty);

        await tester.tap(renglon(OpcionQuePaso.noContesto));
        await esperar(tester);

        final visita = (await visitas(tester)).single;
        final agenda = (await agendas(tester)).single;
        expect(agenda.estado, 'CUMPLIDA');
        expect(agenda.visitaId, visita.id);
        expect(agenda.espacioId, 'esp-1');
        expect(
          [for (final c in encolador.encolados) c.entidad],
          containsAll(['visita', 'agenda', 'house_status']),
          reason: 'todo viaja por el sync',
        );
        await cerrar(tester);
      },
    );

    testWidgets(
      'Deshacer: dado «No contestó» sobre una casa con cita, cuando se toca «Deshacer», la visita '
      'se da de baja, la cita vuelve a PROGRAMADA y la casa vuelve a su color',
      (tester) async {
        await montarReal(
          tester,
          sembrar: () async {
            await local.agendar(agendaDe('age-1'));
          },
        );
        await tester.tap(renglon(OpcionQuePaso.noContesto));
        await esperar(tester);
        expect((await casas(tester)).single.color, 'SIN_CONTESTAR');

        await tester.tap(_deshacer);
        await esperar(tester);

        final visita = (await visitas(tester)).single;
        expect(visita.deletedAt, isNotNull, reason: 'baja lógica: del teléfono no se borra nada');
        final agenda = (await agendas(tester)).single;
        expect(agenda.estado, 'PROGRAMADA');
        expect(agenda.visitaId, isNull);
        expect((await casas(tester)).single.color, 'ENTREVISTA_PROGRAMADA');
        expect(find.text('Se deshizo. Grecia 3307 vuelve a como estaba.'), findsOneWidget);
        await cerrar(tester);
      },
    );

    testWidgets(
      'Deshacer: dado una visita espontánea, cuando se deshace, la agenda creada con ella también '
      'se da de baja y la casa queda sin color',
      (tester) async {
        await montarReal(tester);
        await tester.tap(renglon(OpcionQuePaso.rechazo));
        await esperar(tester);

        await tester.tap(_deshacer);
        await esperar(tester);

        expect((await visitas(tester)).single.deletedAt, isNotNull);
        expect((await agendas(tester)).single.deletedAt, isNotNull);
        expect(
          [
            for (final c in await casas(tester))
              if (c.deletedAt == null) c.color,
          ],
          isEmpty,
          reason: 'sin visita vigente la casa vuelve a «Sin visita» (la fila queda dada de baja)',
        );
        await cerrar(tester);
      },
    );

    testWidgets(
      'Enganche de producción: dado el contexto del propio Navigator (como en main.dart), cuando '
      'se guarda, el aviso «Guardado» sale en el Scaffold de la app y «Deshacer» funciona',
      (tester) async {
        await montarReal(tester);

        await tester.tap(renglon(OpcionQuePaso.noContesto));
        await esperar(tester);

        expect(tester.takeException(), isNull);
        expect(find.byKey(ClavesQuePaso.hoja), findsNothing);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text(_guardadoNoContesto), findsOneWidget);
        await cerrar(tester);
      },
    );

    testWidgets(
      'Doble toque real: dado dos toques seguidos en «No contestó» con la base real, cuando '
      'termina, hay una sola visita y una sola agenda',
      (tester) async {
        await montarReal(tester);

        await tester.tap(renglon(OpcionQuePaso.noContesto));
        await tester.tap(renglon(OpcionQuePaso.noContesto), warnIfMissed: false);
        await esperar(tester);

        expect(await visitas(tester), hasLength(1));
        expect(await agendas(tester), hasLength(1));
        expect(resultados, [true]);
        await cerrar(tester);
      },
    );

    testWidgets(
      'Sin conexión: dado que no hay red, cuando se guarda, todo queda en la cola del sync del '
      'teléfono y el aviso es el mismo',
      (tester) async {
        await montarReal(tester);

        await tester.tap(renglon(OpcionQuePaso.noContesto));
        await esperar(tester);

        expect(encolador.encolados, isNotEmpty);
        expect(find.text(_guardadoNoContesto), findsOneWidget);
        // Ninguna nota ni persona viaja en lo que se encola.
        for (final c in encolador.encolados) {
          expect('${c.payload}', isNot(contains('Grecia')));
        }
        await cerrar(tester);
      },
    );
  });
}
