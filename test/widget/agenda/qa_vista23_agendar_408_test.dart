// QA de «Agendar una visita» (vista 23 A, HU-VIS-001, #408), después del code review. Lo que los tests
// del PR no cruzan: la matriz de tamaños (360x640 y 412x915) x texto 1,0 y 2,0 en cada estado con las
// fuentes reales; si el lector de pantalla puede tocar cada control; los casos límite de las hojas; la
// privacidad de la nota; y el flujo contra la DB real en memoria (la casa pasa a «Entrevista agendada»).
// Cada hallazgo va con `skip` (se corre con `--dart-define=QA_HALLAZGOS=true`). Capturas solo con
// `--dart-define=QA_CAPTURAS=true`, en `.dart_tool/qa_capturas/408_*.png`.
import 'dart:async';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/sync/fakes/encolador_sync_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/data/datasources/agenda_local_data_source_drift.dart';
import 'package:colportores_mobile/features/agenda/data/repositories/agenda_repository_impl.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/franja_horaria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/usecases/agendar_visita_use_case.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart';
import 'package:colportores_mobile/features/mapa/data/services/house_status_updater_drift.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart';
import '../../helpers/campo_falsos.dart';
import '../../helpers/logger_mudo.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_vista23_408_arnes.dart';

const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');
const _verHallazgos = _hallazgos ? false : true;

String _sufijo(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()}_x$e';

bool _tieneTap(WidgetTester tester, Finder f) =>
    tester.getSemantics(f).getSemanticsData().hasAction(SemanticsAction.tap);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('matriz: cada estado en 360x640 y 412x915, texto 1,0 y 2,0', () {
    for (final tamano in [chico, grande]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in Estado408.values) {
          testWidgets(
            '${estado.rotulo} · ${_sufijo(tamano, escala)}: sin overflow y sin texto cortado',
            (tester) async {
              await llegarA(tester, estado, tamano: tamano, escala: escala);
              expect(tester.takeException(), isNull);
              sinTextoCortado408(tester);
              await capturar408(tester, '${estado.archivo}_${_sufijo(tamano, escala)}');
            },
          );
        }
      }
    }
  });

  group('lector de pantalla: cada control se puede activar', () {
    testWidgets(
      'dada la pantalla, cuando se recorren sus controles, entonces todos tienen tap',
      (tester) async {
        final h = tester.ensureSemantics();
        await montar408(tester);
        final controles = <String, Finder>{
          'Cerrar': find.byKey(ClavesAgendarVisita.cerrar),
          'Entrevista': find.text('Entrevista'),
          'Cobranza': find.text('Cobranza'),
          'Día y hora': campo408,
          'Agendar': boton408,
          for (final f in FranjaHoraria.values)
            'franja ${f.etiqueta}': find.byKey(ClavesAgendarVisita.franja(f)),
        };
        final sinTap = <String>[];
        for (final e in controles.entries) {
          await tester.ensureVisible(e.value);
          if (!_tieneTap(tester, e.value)) sinTap.add(e.key);
        }
        h.dispose();
        expect(sinTap, isEmpty, reason: 'sin acción de tocar para el lector: $sinTap');
      },
    ); // arreglado en 20262f7: antes sin SemanticsAction.tap (las 6 franjas no tienen SemanticsAction.tap)

    testWidgets(
      'dada la hoja Día y hora, cuando se recorre, entonces todos sus controles tienen tap',
      (tester) async {
        final h = tester.ensureSemantics();
        await llegarA(tester, Estado408.e02Hoja);
        final controles = <String, Finder>{
          for (var i = 0; i < diasDeAtajo; i++) 'día $i': find.byKey(ClavesAgendarVisita.dia(i)),
          'Otro día…': find.byKey(ClavesAgendarVisita.otroDia),
          'Subir': find.byKey(ClavesAgendarVisita.hojaMas),
          'Bajar': find.byKey(ClavesAgendarVisita.hojaMenos),
          'Hora': find.byKey(ClavesAgendarVisita.hojaHora),
          'Listo': find.byKey(ClavesAgendarVisita.hojaListo),
        };
        final sinTap = <String>[];
        for (final e in controles.entries) {
          await tester.ensureVisible(e.value);
          if (!_tieneTap(tester, e.value)) sinTap.add(e.key);
        }
        h.dispose();
        expect(sinTap, isEmpty, reason: 'sin acción de tocar para el lector: $sinTap');
      },
    ); // arreglado en 20262f7: antes sin SemanticsAction.tap (los 5 chips de día de la hoja no tienen SemanticsAction.tap)

    testWidgets(
      'dada la hoja Esa hora ya pasó, cuando se recorre, entonces sus botones tienen tap',
      (tester) async {
        final h = tester.ensureSemantics();
        await llegarA(tester, Estado408.e03Pregunta);
        for (final k in [
          ClavesAgendarVisita.horaPasadaAgendarIgual,
          ClavesAgendarVisita.horaPasadaCambiar,
        ]) {
          expect(_tieneTap(tester, find.byKey(k)), isTrue);
        }
        h.dispose();
      },
    );

    testWidgets('dado un error al guardar, cuando se anuncia, entonces el aviso es región viva', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await llegarA(tester, Estado408.e06Error);
      final aviso = find.byKey(ClavesAgendarVisita.avisoFalla);
      expect(aviso, findsOneWidget);
      final nodo = tester.getSemantics(
        find.descendant(of: aviso, matching: find.byType(Semantics)).first,
      );
      expect(
        nodo.getSemanticsData().flagsCollection.isLiveRegion ||
            nodo.getSemanticsData().label.isNotEmpty,
        isTrue,
      );
      expect(
        tester.getSemantics(aviso).getSemanticsData().label,
        contains('No pudimos guardar la agenda en tu teléfono'),
      );
      h.dispose();
    });
  });

  group('HU: sugerencia de franja (§8.5.2)', () {
    Future<FranjaHoraria?> franjaPara(WidgetTester tester, int horas, int minutos) async {
      await montar408(tester);
      await tocar408(tester, campo408);
      // La hoja arranca en las 10:00; se llega con los botones de a 5 minutos.
      var actual = 10 * 60;
      final meta = horas * 60 + minutos;
      final subir = find.byKey(ClavesAgendarVisita.hojaMas);
      final bajar = find.byKey(ClavesAgendarVisita.hojaMenos);
      while (actual != meta) {
        final tecla = meta > actual ? subir : bajar;
        await tester.tap(tecla);
        await tester.pump();
        actual += meta > actual ? 5 : -5;
      }
      await tocar408(tester, find.byKey(ClavesAgendarVisita.hojaListo));
      for (final f in FranjaHoraria.values) {
        final chip = tester.widget<ChoiceChip>(find.byKey(ClavesAgendarVisita.franja(f)));
        if (chip.selected) return f;
      }
      return null;
    }

    testWidgets('dada la hora 14:30 (el caso de la HU), entonces sugiere la primera tarde', (
      tester,
    ) async {
      expect(await franjaPara(tester, 14, 30), FranjaHoraria.primeraTarde);
    });

    testWidgets(
      'dada la hora 20:45, cuando ya pasó la última franja, entonces no sugiere ninguna',
      (tester) async {
        expect(await franjaPara(tester, 20, 45), isNull);
      },
    );

    testWidgets('dada la hora 08:00, antes de la primera franja, entonces sugiere la primera', (
      tester,
    ) async {
      expect(await franjaPara(tester, 8, 0), FranjaHoraria.primeraManiana);
    });

    testWidgets('dada una franja elegida a mano, cuando se cambia la hora, entonces se respeta', (
      tester,
    ) async {
      final a = await montar408(tester);
      await tocar408(tester, find.byKey(ClavesAgendarVisita.franja(FranjaHoraria.finDeTarde)));
      await tocar408(tester, campo408);
      for (var i = 0; i < 24; i++) {
        await tester.tap(find.byKey(ClavesAgendarVisita.hojaMas));
        await tester.pump();
      }
      await tocar408(tester, find.byKey(ClavesAgendarVisita.hojaListo));
      await tocar408(tester, boton408);
      expect(a.fake!.recibidas.single.agenda.slotCodigo, 'late_afternoon');
    });
  });

  group('casos límite de las hojas', () {
    testWidgets(
      'dada la pregunta Esa hora ya pasó, cuando se toca fuera, entonces no se agenda nada',
      (tester) async {
        final a = await llegarA(tester, Estado408.e03Pregunta);
        await tester.tapAt(const Offset(180, 20));
        await asentarAgendar(tester);
        expect(find.byKey(ClavesAgendarVisita.horaPasadaAgendarIgual), findsNothing);
        expect(a.fake!.recibidas, isEmpty);
        final fb = tester.widget<FilledButton>(
          find.descendant(of: boton408, matching: find.byType(FilledButton)),
        );
        expect(fb.onPressed, isNotNull);
        expect(find.text('Agendando…'), findsNothing);
        // Y se puede volver a intentar.
        await tocar408(tester, boton408);
        expect(find.byKey(ClavesAgendarVisita.horaPasadaAgendarIgual), findsOneWidget);
      },
    );

    testWidgets(
      'dada la pregunta Esa hora ya pasó, cuando se atrás con el sistema, entonces cierra solo la hoja',
      (tester) async {
        final a = await llegarA(tester, Estado408.e03Pregunta);
        await tester.binding.handlePopRoute();
        await asentarAgendar(tester);
        expect(find.byKey(ClavesAgendarVisita.horaPasadaAgendarIgual), findsNothing);
        expect(find.text('Agendar visita'), findsOneWidget);
        expect(a.fake!.recibidas, isEmpty);
        expect(a.resultados, isEmpty);
      },
    );

    testWidgets('dado Agendar igual tocado dos veces seguidas, entonces se agenda una sola vez', (
      tester,
    ) async {
      final a = await llegarA(tester, Estado408.e03Pregunta);
      final igual = find.byKey(ClavesAgendarVisita.horaPasadaAgendarIgual);
      await tester.tap(igual);
      await tester.tap(igual, warnIfMissed: false);
      await asentarAgendar(tester);
      expect(a.fake!.recibidas, hasLength(1));
      expect(a.fake!.cuantasQuedaron, 1);
      expect(a.resultados, [true]);
      expect(
        a.telefono.recordatorios.llamadas,
        isEmpty,
        reason: 'hora pasada confirmada: sin recordatorio',
      );
    });

    testWidgets(
      'dado Cambiar la hora, cuando se elige una futura, entonces agenda con recordatorio',
      (tester) async {
        final a = await llegarA(tester, Estado408.e03Pregunta);
        await tocar408(tester, find.byKey(ClavesAgendarVisita.horaPasadaCambiar));
        expect(find.byKey(ClavesAgendarVisita.hojaListo), findsOneWidget);
        await tocar408(tester, find.byKey(ClavesAgendarVisita.dia(1)));
        await tocar408(tester, find.byKey(ClavesAgendarVisita.hojaListo));
        expect(find.byKey(ClavesAgendarVisita.errorHora), findsNothing);
        await tocar408(tester, boton408);
        expect(a.fake!.cuantasQuedaron, 1);
        expect(a.telefono.recordatorios.programados, hasLength(1));
      },
    );

    testWidgets('dada la hoja a las 23:55, cuando se sube la hora, entonces el día avanza', (
      tester,
    ) async {
      final a = await montar408(tester);
      await tocar408(tester, campo408);
      // 10:00 + 168 pasos de 5 min = 00:00: la hoja cuenta la hora en módulo 24 h.
      for (var i = 0; i < 168; i++) {
        await tester.tap(find.byKey(ClavesAgendarVisita.hojaMas));
        await tester.pump();
      }
      expect(find.text('00:00'), findsOneWidget);
      await tocar408(tester, find.byKey(ClavesAgendarVisita.hojaListo));
      await tocar408(tester, boton408);
      // «Mañana 23:55» + 5 min tiene que ser «pasado mañana 00:00», no «mañana 00:00» (23 h antes).
      final fecha = a.fake!.recibidas.single.agenda.fechaProgramada.toLocal();
      expect(fecha.isAfter(DateTime(2026, 10, 25)), isTrue);
    }, skip: _verHallazgos); // skip: QA #408 — la hoja pasa de 23:55 a 00:00 sin avanzar el día.
  });

  group('doble toque y acciones superpuestas', () {
    testWidgets(
      'dado un guardado en curso, cuando se toca Agendar tres veces, entonces llega una sola agenda',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda()..compuerta = Completer<void>();
        final a = await montar408(tester, fake: repo);
        for (var i = 0; i < 3; i++) {
          await tester.tap(boton408, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(repo.recibidas, hasLength(1));
        repo.compuerta!.complete();
        await asentarAgendar(tester);
        expect(repo.cuantasQuedaron, 1);
        expect(a.telefono.recordatorios.programados, hasLength(1));
        expect(a.resultados, [true]);
      },
    );

    testWidgets(
      'dado un guardado en curso, cuando se intenta tocar un chip, la franja o el campo, entonces no pasa nada',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda()..compuerta = Completer<void>();
        await montar408(tester, fake: repo);
        await tester.tap(boton408);
        await tester.pump(const Duration(milliseconds: 20));
        await tester.tap(
          find.byKey(ClavesAgendarVisita.franja(FranjaHoraria.mediaTarde)),
          warnIfMissed: false,
        );
        await tester.tap(campo408, warnIfMissed: false);
        await tester.tap(find.text('Cobranza'), warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 20));
        expect(find.byKey(ClavesAgendarVisita.hojaListo), findsNothing);
        expect(repo.recibidas.single.agenda.tipo, TipoAgenda.entrevista);
        expect(repo.recibidas.single.agenda.slotCodigo, 'mid_morning');
        repo.compuerta!.complete();
        await asentarAgendar(tester);
      },
    );

    testWidgets(
      'dada una falla que lanza una excepción, cuando se agenda, entonces el botón se libera y el aviso no filtra lo escrito',
      (tester) async {
        const secreto = 'Nota con 099123456 y calle Mataojo 2044';
        final repo = AgendaRepositorioQueAgenda()..lanzar = Exception(secreto);
        await montar408(tester, fake: repo);
        await tester.enterText(find.byType(TextField), secreto);
        await tocar408(tester, boton408);
        expect(
          find.textContaining('099123456'),
          findsOneWidget,
          reason: 'solo el campo de la nota',
        );
        expect(
          find.text('No pudimos guardar la agenda en tu teléfono. Probá de nuevo.'),
          findsOneWidget,
        );
        expect(find.text('Agendando…'), findsNothing);
        final fb = tester.widget<FilledButton>(
          find.descendant(of: boton408, matching: find.byType(FilledButton)),
        );
        expect(fb.onPressed, isNotNull);
        // Reintentar guarda con la nota que estaba escrita.
        await tocar408(tester, boton408);
        expect(repo.cuantasQuedaron, 1);
        expect(repo.recibidas.last.nota?.texto, secreto);
      },
    );

    testWidgets(
      'dadas dos fallas seguidas y un cambio de tipo en el medio, cuando se reintenta, entonces conserva el id y lo tipeado',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda()
          ..fallas.addAll([const FailureInesperado(), const FailureInesperado()]);
        await montar408(tester, fake: repo);
        await tester.enterText(find.byType(TextField), 'Ñandú 🦤');
        await tocar408(tester, boton408);
        await tocar408(tester, find.text('Cobranza'));
        await tocar408(tester, boton408);
        await tocar408(tester, boton408);
        expect(repo.recibidas.map((r) => r.agenda.id).toSet(), hasLength(1));
        expect(repo.recibidas.last.agenda.tipo, TipoAgenda.cobranza);
        expect(repo.cuantasQuedaron, 1);
        expect(repo.recibidas.last.nota?.texto, 'Ñandú 🦤');
      },
    );
  });

  group('datos límite', () {
    testWidgets(
      'dada una nota pegada de 600 emoji, cuando se agenda, entonces guarda 500 y ninguno partido',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda();
        await montar408(tester, fake: repo);
        await tester.enterText(find.byType(TextField), List.filled(600, '👩🏽‍🦰').join());
        await tocar408(tester, boton408);
        final texto = repo.recibidas.single.nota!.texto;
        expect(texto.characters.length, 500);
        // Ningún surrogate suelto: el texto se puede codificar sin reemplazos.
        expect(String.fromCharCodes(texto.runes), texto);
        expect(texto.codeUnits.where((u) => u >= 0xD800 && u <= 0xDFFF).length % 2, 0);
      },
    );

    testWidgets(
      'dada una nota de solo espacios y saltos, cuando se agenda, entonces no se crea la nota',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda();
        await montar408(tester, fake: repo);
        await tester.enterText(find.byType(TextField), '   \n\n\t  ');
        await tocar408(tester, boton408);
        expect(repo.recibidas.single.nota, isNull);
      },
    );

    testWidgets(
      'dada una nota con caracteres especiales, cuando se agenda, entonces llega tal cual (recortada en los bordes)',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda();
        await montar408(tester, fake: repo);
        await tester.enterText(find.byType(TextField), '  <b>"Ñ"</b>; DROP TABLE agenda;--\n  ');
        await tocar408(tester, boton408);
        expect(repo.recibidas.single.nota!.texto, '<b>"Ñ"</b>; DROP TABLE agenda;--');
      },
    );

    testWidgets(
      'dado un nombre y una dirección larguísimos, cuando se abre, entonces nada desborda a 360x640 x2',
      (tester) async {
        await montar408(
          tester,
          escala: 2,
          personas: [
            clienteDePersonas(
              'p1',
              'Maximiliano Alejandro de los Santos',
              apellido: 'Fernández-Rodríguez y Pérez del Castillo',
            ),
          ],
          casa: (
            espacio: espacioDePersonas(
              numeroDepto: 'Torre Norte, piso 14, Depto 1403 bis',
              piso: null,
            ),
            ubicacion: ubicacionDePersonas(
              calle: 'Avenida General Don José Gervasio Artigas y Bulevar Batlle y Ordóñez',
              numero: '123456',
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        sinTextoCortado408(tester);
      },
    );
  });

  group('el error queda a la vista', () {
    testWidgets(
      'dado el formulario desplazado a la nota (360x640, x2), cuando falla el guardado, entonces el aviso se ve',
      (tester) async {
        final repo = AgendaRepositorioQueAgenda()..fallas.add(const FailureInesperado());
        await montar408(tester, fake: repo, escala: 2);
        await tester.ensureVisible(find.byType(TextField));
        await tester.pump();
        await tocar408(tester, boton408);
        final aviso = tester.getRect(find.byKey(ClavesAgendarVisita.avisoFalla));
        final tope = tester.getRect(boton408).top;
        expect(
          aviso.bottom > 0 && aviso.top < tope,
          isTrue,
          reason:
              'el aviso rojo quedó fuera de la vista (arriba, $aviso): solo cambió la etiqueta del botón',
        );
      },
      skip: _verHallazgos,
    ); // skip: QA #408 — con el formulario desplazado el aviso de error queda fuera de vista.
  });

  group('teclado abierto', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'dado el teclado en la nota (x$escala, 360x640), cuando se mira, entonces el botón Agendar queda a la vista',
        (tester) async {
          await montar408(tester, escala: escala);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          addTearDown(tester.view.resetViewInsets);
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(estaEnPantalla408(tester, boton408), isTrue);
          final alto = tester.getSize(boton408).height;
          expect(alto, greaterThanOrEqualTo(48));
        },
      );
    }
  });

  group('privacidad', () {
    test('dados los parámetros con una nota, cuando se imprimen, entonces no sale la nota', () {
      final params = AgendarVisitaParams(
        ids: const IdsAgendarVisita(agenda: 'a', nota: 'n'),
        espacioId: 'esp-1',
        colportorId: 'col-1',
        tipo: TipoAgenda.entrevista,
        fechaProgramada: DateTime(2026, 10, 24, 10),
        nota: 'SECRETO ñandú 099123456',
        direccion: 'Mataojo 2044',
      );
      expect(params.toString(), isNot(contains('SECRETO')));
      expect(params.toString(), isNot(contains('099123456')));
    });
  });

  group('contra la DB real en memoria (HU: criterios de aceptación)', () {
    late AppDatabase db;
    late EncoladorSyncEnMemoria encolador;
    late AgendaRepositoryImpl repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      encolador = EncoladorSyncEnMemoria();
      repo = AgendaRepositoryImpl(
        AgendaLocalDataSourceDrift(
          db,
          encolador: encolador,
          estadoDeLasCasas: HouseStatusUpdaterDrift(db, encolador: encolador),
        ),
      );
    });

    Future<void> cerrar(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(db.close);
    }

    testWidgets(
      'Escenario: Agendar entrevista · dada la casa, cuando se agenda, entonces la agenda queda PROGRAMADA, con recordatorio y la casa «interview_scheduled»',
      (tester) async {
        await tester.runAsync(() => sembrarCasa(db));
        final a = await montar408(tester, repoReal: repo, espacioPersonaId: 'ep-1');
        await tocar408(tester, boton408);
        expect(a.resultados, [true]);
        final agendas = await tester.runAsync(() => db.select(db.agendas).get());
        expect(agendas, hasLength(1));
        expect(agendas!.single.estado, 'PROGRAMADA');
        expect(agendas.single.tipo, 'ENTREVISTA');
        expect(agendas.single.slotCodigo, 'mid_morning');
        expect(agendas.single.espacioPersonaId, 'ep-1');
        expect(a.telefono.recordatorios.programados, hasLength(1));
        final casas = await tester.runAsync(() => db.select(db.houseStatuses).get());
        expect(casas!.single.color, 'ENTREVISTA_PROGRAMADA');
        await cerrar(tester);
      },
    );

    testWidgets(
      'dada la hora pasada confirmada, cuando se agenda igual, entonces queda agendada sin recordatorio',
      (tester) async {
        await tester.runAsync(() => sembrarCasa(db));
        final a = await montar408(tester, repoReal: repo, espacioPersonaId: 'ep-1');
        await hoyALas11(tester);
        await tocar408(tester, boton408);
        await tocar408(tester, find.byKey(ClavesAgendarVisita.horaPasadaAgendarIgual));
        expect(a.resultados, [true]);
        expect((await tester.runAsync(() => db.select(db.agendas).get()))!, hasLength(1));
        expect(a.telefono.recordatorios.programados, isEmpty);
        await cerrar(tester);
      },
    );

    testWidgets(
      'dada una casa que no está en la base, cuando se abre, entonces «Agendar» queda deshabilitado, avisa y se puede salir',
      (tester) async {
        final a = await montar408(tester, repoReal: repo, sinCasa: true);
        final boton = tester.widget<FilledButton>(
          find.descendant(of: boton408, matching: find.byType(FilledButton)),
        );
        expect(boton.onPressed, isNull);
        expect(
          find.text('Esta casa ya no está en tu teléfono. Volvé al mapa y elegila de nuevo.'),
          findsWidgets,
        );
        await tester.tap(boton408, warnIfMissed: false);
        await asentarAgendar(tester);
        expect(a.resultados, isEmpty);
        expect((await tester.runAsync(() => db.select(db.agendas).get()))!, isEmpty);
        // La X sigue disponible: no queda trabada.
        await tocar408(tester, find.byKey(ClavesAgendarVisita.cerrar));
        expect(find.text('Agendar visita'), findsNothing);
        expect(a.resultados, [false]);
        await cerrar(tester);
      },
    );
  });
}
