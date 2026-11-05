// QA de «Vender» con varias personas entrevistadas y de «Ir a la entrevista» (vista 39, C·06 / C·07 / R·05;
// #661, PR #668): los criterios del issue con su texto literal, los casos límite de cada flujo (dobles toques,
// scrim, bajas a mitad de camino, la otra entrevista que desaparece, reentradas) y que cada aviso y cada
// botón queden a la vista sin desplazarse en 360×640 con texto 2,0.
//
// Los hallazgos van con `skip` (`--dart-define=QA_HALLAZGOS=true` los corre). Las capturas solo con
// `--dart-define=QA_CAPTURAS=true` (`.dart_tool/qa_capturas/661_*.png`, nunca se commitean).
import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/persona_repository.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_con_quien.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_vista39_661_arnes.dart';

Finder get _filaVender => find.byKey(ClavesQuePaso.opcion(OpcionQuePaso.vender));
Finder get _hojaConQuien => find.byType(HojaConQuien);
Finder get _ventaPagina => find.byKey(const Key('nueva_venta_pagina'));
Finder _dentroDeLaHoja(Finder f) => find.descendant(of: _hojaConQuien, matching: f);
Finder get _botonVender => _dentroDeLaHoja(find.byType(FilledButton));

/// El rectángulo de la pantalla del test.
Rect _pantalla(WidgetTester tester) => Offset.zero & tester.view.physicalSize;

void main() {
  usarFuentesReales = true;

  group('criterios del issue, con el texto literal', () {
    testWidgets('con una sola persona entrevistada: sin preguntar y con el nombre en la ayuda', (
      tester,
    ) async {
      final a = await llegarA661(tester, Estado661.quePasoVarias);
      // Se rearma con una sola entrevistada: Ana ya no cuenta como entrevistada.
      a.lector.porVinculo.remove('ep-2');
      await tester.binding.handlePopRoute();
      await a.asentar(tester);
      await a.abrirQuePaso(tester);

      expect(find.text('Registrar la venta de Pedro Gómez'), findsOneWidget);
      expect(find.text('Elegís a quién le vendés'), findsNothing);
      await a.elegir(tester, OpcionQuePaso.vender);
      expect(_hojaConQuien, findsNothing, reason: 'una sola: no se pregunta');
      expect(a.ventas.single.espacioPersonaId, 'ep-1');
    });

    testWidgets('con dos: la ayuda y la hoja dicen lo que fijó la decisión del 05/11 (P2)', (
      tester,
    ) async {
      final a = await llegarA661(tester, Estado661.quePasoVarias);
      expect(find.text('Elegís a quién le vendés'), findsOneWidget);
      await capturar661(tester, 'c06_varias_360x640');

      await a.elegir(tester, OpcionQuePaso.vender);

      // El título queda el de C·07; el botón es «Vender»; atrás es «Volver».
      expect(_dentroDeLaHoja(find.text('¿Con quién fue la entrevista?')), findsOneWidget);
      expect(_dentroDeLaHoja(find.text('Vender')), findsOneWidget);
      expect(_dentroDeLaHoja(find.text('Volver')), findsOneWidget);
      expect(find.text('Empezar entrevista'), findsNothing);
      expect(find.text('+ Alguien nuevo'), findsNothing);
      expect(find.text('Todavía no sé con quién'), findsNothing);
      await capturar661(tester, 'c07_vender_360x640');
    });

    testWidgets('tres en la casa, una sin entrevista: la lista ofrece solo las dos entrevistadas', (
      tester,
    ) async {
      await llegarA661(tester, Estado661.conQuienVendeTres);
      expect(_dentroDeLaHoja(find.text('Ana Gómez')), findsOneWidget);
      expect(_dentroDeLaHoja(find.text('Pedro Gómez')), findsOneWidget);
      expect(_dentroDeLaHoja(find.text('Luis Díaz')), findsNothing);
      await capturar661(tester, 'c07_vender_tres_360x640');
    });

    testWidgets('el aviso de «Entrevista dada» no cambia el texto y suma «Ir a la entrevista»', (
      tester,
    ) async {
      await llegarA661(tester, Estado661.quePasoOtraEnCurso);
      expect(
        find.textContaining('Ya tenés una entrevista en curso en Grecia 3307'),
        findsOneWidget,
      );
      expect(find.text('Ir a la entrevista'), findsOneWidget);
      await capturar661(tester, 'c06_otra_en_curso_360x640');
    });
  });

  group('«Vender» → «¿Con quién?»: casos límite', () {
    testWidgets('doble tap en el renglón «Vender» de «¿Qué pasó?»: una sola «¿Con quién?»', (
      tester,
    ) async {
      final a = await llegarA661(tester, Estado661.quePasoVarias);

      await tester.ensureVisible(_filaVender);
      await tester.tap(_filaVender);
      await tester.tap(_filaVender, warnIfMissed: false);
      await a.asentar(tester);

      expect(_hojaConQuien, findsOneWidget);
      expect(a.ventas, isEmpty);
    });

    testWidgets('tocar fuera de la hoja la cierra sin guardar ni avisar, y se puede reintentar', (
      tester,
    ) async {
      final a = await llegarA661(tester, Estado661.conQuienVende);

      await tester.tapAt(const Offset(180, 8));
      await a.asentar(tester);

      expect(_hojaConQuien, findsNothing);
      expect(a.ventas, isEmpty);
      expect(a.entorno.ventas.recibidas, isEmpty);
      expect(find.byKey(ClavesQuePaso.falla), findsNothing);
      expect(find.byKey(ClavesQuePaso.guardando), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(ClavesQuePaso.hoja), findsOneWidget);
      await a.elegir(tester, OpcionQuePaso.vender);
      expect(_hojaConQuien, findsOneWidget);
    });

    testWidgets('elegir y volver a elegir: la venta es de la ÚLTIMA elegida', (tester) async {
      final a = await llegarA661(tester, Estado661.conQuienVende);

      await tester.tap(_dentroDeLaHoja(find.text('Pedro Gómez')));
      await tester.pump();
      await tester.tap(_dentroDeLaHoja(find.text('Ana Gómez')));
      await tester.pump();
      await tester.tap(_dentroDeLaHoja(find.text('Pedro Gómez')));
      await tester.pump();
      await tester.tap(_botonVender);
      await a.asentar(tester);

      expect(a.ventas.single.espacioPersonaId, 'ep-1');
      expect(_ventaPagina, findsOneWidget);
    });

    testWidgets('misma fecha de entrevista: queda primera y elegida la que ya iba primera', (
      tester,
    ) async {
      final a = await llegarA661(tester, Estado661.quePasoVarias);
      a.lector.porVinculo['ep-2'] = ayer661; // igual que Pedro
      await tester.binding.handlePopRoute();
      await a.asentar(tester);
      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.vender);

      expect(
        tester.getTopLeft(_dentroDeLaHoja(find.text('Pedro Gómez'))).dy,
        lessThan(tester.getTopLeft(_dentroDeLaHoja(find.text('Ana Gómez'))).dy),
      );
      await tester.tap(_botonVender);
      await a.asentar(tester);
      expect(a.ventas.single.espacioPersonaId, 'ep-1');
    });

    testWidgets('a mitad de camino una de las dos se da de baja: la venta nunca es de la baja', (
      tester,
    ) async {
      final a = await llegarA661(tester, Estado661.quePasoVarias);
      final repo = a.contenedor(tester).read(personaRepositoryProvider) as PersonaRepositorioFalso;
      // Ana (la más reciente) se da de baja con «¿Qué pasó?» abierta.
      await repo.darDeBaja(personaId: _personaDe(repo, 'ep-2'), ahora: hoy661);
      await a.asentar(tester);

      await a.elegir(tester, OpcionQuePaso.vender);

      expect(a.ventas.map((v) => v.espacioPersonaId), isNot(contains('ep-2')));
      expect(find.byKey(ClavesQuePaso.guardando), findsNothing);
    });

    testWidgets('a mitad de camino se dan de baja las dos: nada se guarda y nada queda trabado', (
      tester,
    ) async {
      final a = await llegarA661(tester, Estado661.quePasoVarias);
      final repo = a.contenedor(tester).read(personaRepositoryProvider) as PersonaRepositorioFalso;
      await repo.darDeBaja(personaId: _personaDe(repo, 'ep-1'), ahora: hoy661);
      await repo.darDeBaja(personaId: _personaDe(repo, 'ep-2'), ahora: hoy661);
      await a.asentar(tester);

      await a.elegir(tester, OpcionQuePaso.vender);

      expect(a.ventas, isEmpty);
      expect(_hojaConQuien, findsNothing);
      expect(tester.takeException(), isNull);
      expect(find.byKey(ClavesQuePaso.guardando), findsNothing);
      expect(find.byKey(ClavesQuePaso.hoja), findsOneWidget, reason: '«¿Qué pasó?» sigue abierta');
      // Se puede elegir otra cosa: «Cancelar» cierra.
      await tester.ensureVisible(find.byKey(ClavesQuePaso.cancelar));
      await tester.tap(find.byKey(ClavesQuePaso.cancelar));
      await a.asentar(tester);
      expect(a.resultados, [false]);
    });

    testWidgets(
      'a mitad de camino se dan de baja las dos: el toque en «Vender» dice algo (no es un no-hacer-nada mudo)',
      (tester) async {
        final a = await llegarA661(tester, Estado661.quePasoVarias);
        final repo =
            a.contenedor(tester).read(personaRepositoryProvider) as PersonaRepositorioFalso;
        await repo.darDeBaja(personaId: _personaDe(repo, 'ep-1'), ahora: hoy661);
        await repo.darDeBaja(personaId: _personaDe(repo, 'ep-2'), ahora: hoy661);
        await a.asentar(tester);

        await a.elegir(tester, OpcionQuePaso.vender);

        expect(
          find.byKey(ClavesQuePaso.falla),
          findsOneWidget,
          reason: 'el toque terminó sin hacer nada ni decir por qué',
        );
      },
      // skip: QA #661 — si las entrevistadas ya no están, «Vender» cierra «¿Con quién?» sin aviso ni salida.
      skip: !verHallazgos661,
    );
  });

  group('«Ir a la entrevista»: casos límite', () {
    testWidgets('el aviso es región viva y el botón es un nodo aparte con su nombre y su toque', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await llegarA661(tester, Estado661.quePasoOtraEnCurso);

      final aviso = tester.getSemantics(find.byKey(ClavesQuePaso.falla));
      expect(aviso.flagsCollection.isLiveRegion, isTrue);
      final boton = tester.getSemantics(irALaEntrevista661);
      expect(boton.label, 'Ir a la entrevista');
      expect(boton.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('360×640 con texto 2,0: el aviso y su botón están a la vista, sin desplazar', (
      tester,
    ) async {
      await llegarA661(tester, Estado661.quePasoOtraEnCurso, escala: 2);

      expect(tester.takeException(), isNull);
      final r = tester.getRect(irALaEntrevista661);
      expect(_pantalla(tester).contains(r.topLeft), isTrue);
      expect(_pantalla(tester).contains(r.bottomRight), isTrue);
      expect(irALaEntrevista661.hitTestable(), findsOneWidget);
      await capturar661(tester, 'c06_otra_en_curso_360x640_x2');
    });

    testWidgets(
      '360×640 con texto 2,0, de vuelta de R·05: el aviso y su botón vuelven a la vista',
      (tester) async {
        await llegarA661(tester, Estado661.quePasoOtraVolvio, escala: 2);

        expect(tester.takeException(), isNull);
        expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsNothing);
        expect(irALaEntrevista661.hitTestable(), findsOneWidget);
        final r = tester.getRect(irALaEntrevista661);
        expect(_pantalla(tester).contains(r.topLeft), isTrue);
        expect(_pantalla(tester).contains(r.bottomRight), isTrue);
      },
    );

    testWidgets(
      '«Vender» de «¿Con quién?» y «Volver» se ven sin desplazar en 360×640 con texto 2,0',
      (tester) async {
        await llegarA661(tester, Estado661.conQuienVendeTres, escala: 2);

        expect(tester.takeException(), isNull);
        expect(_botonVender.hitTestable(), findsOneWidget);
        expect(_dentroDeLaHoja(find.text('Volver')).hitTestable(), findsOneWidget);
        await capturar661(tester, 'c07_vender_tres_360x640_x2');
      },
    );

    testWidgets('la otra entrevista desaparece antes del toque: no queda nada trabado', (
      tester,
    ) async {
      final a = await llegarA661(tester, Estado661.quePasoOtraEnCurso);
      // La entrevista de la otra casa ya no existe (se terminó por otro lado).
      a.montaje.almacen.guardadas.clear();
      a.contenedor(tester).invalidate(entrevistaEnCursoProvider('col-1'));
      await a.asentar(tester);

      await tocarIrALaEntrevista661(tester, a);

      expect(tester.takeException(), isNull);
      expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsNothing);
      expect(find.byKey(ClavesQuePaso.guardando), findsNothing);
      expect(a.entrevistas, isEmpty, reason: 'la de esta casa no se empezó sola');
      // Sea cual sea la salida, la persona puede volver a tocar «Entrevista dada».
      if (find.byKey(ClavesQuePaso.hoja).evaluate().isEmpty) {
        await a.abrirQuePaso(tester);
      }
      await a.elegir(tester, OpcionQuePaso.entrevistaDada);
      // Ya no hay aviso: con dos personas en la casa se pregunta «¿Con quién?».
      expect(find.byKey(ClavesQuePaso.falla), findsNothing);
      expect(_hojaConQuien, findsOneWidget);
    });

    testWidgets(
      'R·05 → R·06 → «Sí, registrar la venta» → atrás: la otra sigue en curso y el botón vuelve',
      (tester) async {
        final a = await llegarA661(tester, Estado661.r05DesdeElAviso);

        await a.tocarKey(tester, ClavesEntrevista.finalizar);
        await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
        await a.tocarKey(tester, const Key('venta_atras'));
        await a.asentar(tester, 80);

        expect(a.montaje.almacen.guardadas['col-1']!.espacioId, 'esp-9', reason: 'sigue en curso');
        expect(a.entorno.ventas.recibidas, isEmpty);
        expect(find.byKey(ClavesQuePaso.falla), findsOneWidget);
        expect(
          irALaEntrevista661.hitTestable(),
          findsOneWidget,
          reason: 'el aviso de la venta que no se guardó no puede tapar el botón',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('tres idas y vueltas seguidas: el botón sigue vivo y no se apilan entrevistas', (
      tester,
    ) async {
      final a = await llegarA661(tester, Estado661.quePasoOtraEnCurso);

      for (var i = 0; i < 3; i++) {
        await tocarIrALaEntrevista661(tester, a);
        expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsOneWidget);
        await tester.binding.handlePopRoute();
        await a.asentar(tester);
        expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsNothing);
        expect(irALaEntrevista661, findsOneWidget);
      }
      expect(a.entrevistas, isEmpty);
      expect(find.byKey(ClavesQuePaso.guardando), findsNothing);
    });

    testWidgets('mientras corre «Ir a la entrevista» no se puede cancelar ni tocar otro renglón', (
      tester,
    ) async {
      final a = await llegarA661(tester, Estado661.quePasoOtraEnCurso);

      await tester.ensureVisible(irALaEntrevista661);
      await tester.tap(irALaEntrevista661);
      // R·05 recién abriéndose: «¿Qué pasó?» queda debajo y no admite nada.
      await a.asentar(tester);
      expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsOneWidget);
      expect(a.resultados, isEmpty, reason: '«¿Qué pasó?» no se cerró por debajo');
    });
  });
}

/// El id de la persona del vínculo [vinculoId] (el repositorio falso la guarda con él).
String _personaDe(PersonaRepository repo, String vinculoId) {
  final n = vinculoId.replaceFirst('ep-', '');
  return clienteDePersonas(n, 'x').persona.id;
}
