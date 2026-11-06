// QA de «Entrevista dada» y «Vender» de «¿Qué pasó?» (vista 39, R·04 → R·08, C·06 y C·07; #648, PR #657):
// la HU y la decisión de Cristian del 04/11 («Vender desde el mapa») contra lo que se ve, en la matriz de
// tamaños (360x640 y 412x915) y de escala de texto (1,0 y 2,0), con fuentes reales.
//
// Los hallazgos van con `skip`: `--dart-define=QA_HALLAZGOS=true` los corre para verlos fallar. Las capturas
// solo se sacan con `--dart-define=QA_CAPTURAS=true` (`.dart_tool/qa_capturas/648_*.png`, nunca se commitean).
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart'
    show TipoResultadoVisita;
import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_con_quien.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_registrar_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrevista_dada_648_arnes.dart';
import '../../helpers/persona_falsos.dart';
import '../../helpers/qa_vista39_648_arnes.dart';

Finder get _vender => find.byKey(ClavesQuePaso.opcion(OpcionQuePaso.vender));
Finder get _entrevistaDada => find.byKey(ClavesQuePaso.opcion(OpcionQuePaso.entrevistaDada));
Finder get _hojaQuePaso => find.byKey(ClavesQuePaso.hoja);

void main() {
  // Matriz: cada estado en cada tamaño y escala, sin desborde y con la captura.
  for (final tamano in [t360x640, t412x915]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in Estado648.values) {
        testWidgets('${estado.name} · ${sufijo648(tamano, escala)}: sin desborde ni excepciones', (
          tester,
        ) async {
          await llegarA648(tester, estado, tamano: tamano, escala: escala);
          await tester.pump(const Duration(milliseconds: 300));

          expect(tester.takeException(), isNull, reason: 'sin overflow ni errores');
          await capturar648(tester, '${estado.name}_${sufijo648(tamano, escala)}');
        });
      }
    }
  }

  group('criterios de aceptación del issue #648 (texto literal)', () {
    testWidgets('«¿Qué pasó?» ofrece «Entrevista dada» (hoy no se dibuja sin destino)', (
      tester,
    ) async {
      final a = Arnes648();
      await a.montar(tester);
      await a.abrirQuePaso(tester);

      expect(_entrevistaDada, findsOneWidget);
      expect(find.text('Entrevista dada'), findsOneWidget);
    });

    testWidgets('con una entrevista dada previa en la casa «¿Qué pasó?» ofrece «Vender»', (
      tester,
    ) async {
      final a = Arnes648();
      a.lector.porVinculo['ep-1'] = ayer648;
      await a.montar(tester);
      await a.abrirQuePaso(tester);

      expect(_vender, findsOneWidget);
      expect(find.text(TextosRegistrarVisita.vender), findsOneWidget);
      expect(find.text('Registrar la venta de Pedro Gómez'), findsOneWidget);
    });

    testWidgets('sin entrevista previa no se ofrece «Vender»', (tester) async {
      final a = Arnes648();
      await a.montar(tester);
      await a.abrirQuePaso(tester);

      expect(_vender, findsNothing);
    });

    testWidgets(
      '«No, guardar y volver al mapa» guarda la visita como «Entrevista dada» y vuelve al mapa',
      (tester) async {
        final a = Arnes648();
        await a.montar(tester);
        await a.hastaLaHoraDeSalida(tester);
        await a.tocarKey(tester, ClavesEntrevista.guardarYVolver);

        final visita = a.montaje.agenda.recibidas.single.visita;
        expect(visita.tipoResultado, TipoResultadoVisita.entrevista);
        expect(a.resultados, [true]);
        expect(_hojaQuePaso, findsNothing);
      },
    );
  });

  group('casos límite del flujo', () {
    testWidgets('atrás en R·06 deja la entrevista en curso, con su aviso fijo, y no guarda nada', (
      tester,
    ) async {
      final a = Arnes648();
      await a.montar(tester);
      await a.hastaLaHoraDeSalida(tester);

      await tester.binding.handlePopRoute();
      await a.asentar(tester);

      expect(find.byKey(ClavesEntrevista.hojaTermino), findsNothing);
      expect(a.montaje.agenda.recibidas, isEmpty);
      expect(a.montaje.almacen.guardadas, hasLength(1));
      expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);
    });

    testWidgets(
      'R·07 → «Sí, registrar la venta» → venta → R·08: una visita VENTA y nada en curso',
      (tester) async {
        final a = Arnes648();
        a.montaje.rota.fallaAlGuardar = true;
        a.montaje.ultimaVisita.fecha = DateTime(2026, 10, 23, 13, 30);
        await a.montar(tester);
        await a.hastaLaEntrevista(tester);
        expect(find.byKey(ClavesEntrevista.avisoSinInicio), findsOneWidget);

        await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
        await a.armarLaVenta(tester);
        await a.registrarSinFecha(tester);

        expect(a.montaje.agenda.recibidas.single.visita.tipoResultado, TipoResultadoVisita.venta);
        expect(a.entorno.ventas.recibidas.single.venta.numeroTalonario, '0039');
        expect(a.montaje.almacen.guardadas, isEmpty);
        expect(a.salidasDeEntrevista.single, isA<VentaRegistradaEnLaCasa>());
        expect(a.resultados, [true], reason: 'tras guardar (05/11): la hoja de la casa se cierra');
      },
    );

    testWidgets('doble tap en «Vender»: una sola venta y un solo gancho', (tester) async {
      final a = Arnes648();
      a.lector.porVinculo['ep-1'] = ayer648;
      await a.montar(tester);
      await a.abrirQuePaso(tester);

      final renglon = _vender;
      await tester.ensureVisible(renglon);
      await tester.pump();
      await tester.tap(renglon);
      await tester.tap(renglon, warnIfMissed: false);
      await a.asentar(tester);

      expect(a.ventas, hasLength(1));
      expect(find.byKey(const Key('nueva_venta_pagina')), findsOneWidget);
    });

    testWidgets('«Vender» con una entrevista en curso en otra casa no la toca', (tester) async {
      final a = Arnes648();
      a.lector.porVinculo['ep-1'] = ayer648;
      await a.montar(tester);
      await a
          .contenedor(tester)
          .read(entrevistaEnCursoProvider('col-1').notifier)
          .empezar(espacioId: 'esp-9', espacioPersonaId: 'ep-9');
      await a.asentar(tester);
      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.vender);
      await a.armarLaVenta(tester);
      await a.registrarSinFecha(tester);

      expect(a.salidasDeVenta.single, isA<VentaRegistradaEnLaCasa>());
      expect(a.montaje.almacen.guardadas['col-1']!.espacioId, 'esp-9');
      // La visita «Venta» es de esta casa, no de la otra donde hay una entrevista en curso.
      final visita = a.montaje.agenda.recibidas.single.visita;
      expect(visita.tipoResultado, TipoResultadoVisita.venta);
      expect(visita.espacioId, 'esp-1');
    });

    testWidgets(
      'R·04 sin personas: con nombre vacío o de espacios no se empieza ninguna entrevista',
      (tester) async {
        final a = Arnes648();
        await a.montar(tester, personas: []);
        await a.hastaLaEntrevista(tester);
        final boton = find.widgetWithText(FilledButton, TextosConQuien.empezar);
        expect(boton, findsOneWidget);

        // Vacío: se puede tocar (dice qué falta) pero no guarda nada.
        await tester.tap(boton);
        await a.asentar(tester);
        expect(a.montaje.almacen.guardadas, isEmpty);
        expect(a.entrevistas, isEmpty);

        // Solo espacios.
        await tester.enterText(find.byType(TextField).first, '     ');
        await tester.pump();
        await tester.tap(boton);
        await a.asentar(tester);
        expect(a.montaje.almacen.guardadas, isEmpty);
        expect(a.entrevistas, isEmpty);
        expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsNothing);
      },
    );

    testWidgets('R·04 sin personas: un nombre con emoji y acentos empieza la entrevista', (
      tester,
    ) async {
      final a = Arnes648();
      await a.montar(tester, personas: []);
      await a.hastaLaEntrevista(tester);

      await tester.enterText(find.byType(TextField).first, 'Zoë 😀');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, TextosConQuien.empezar));
      await a.asentar(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsOneWidget);
      expect(a.montaje.almacen.guardadas, hasLength(1));
    });
  });

  group('hallazgos', () {
    testWidgets(
      'misma casa, otra persona: si ya hay una entrevista en curso con Pedro, elegir a Ana no la '
      'cambia en silencio',
      (tester) async {
        final a = Arnes648();
        await a.montar(
          tester,
          personas: [
            clienteDePersonas('1', 'Pedro', apellido: 'Gómez'),
            clienteDePersonas('2', 'Ana', apellido: 'Gómez'),
          ],
        );
        await a
            .contenedor(tester)
            .read(entrevistaEnCursoProvider('col-1').notifier)
            .empezar(espacioId: 'esp-1', espacioPersonaId: 'ep-1');
        await a.asentar(tester);

        await a.abrirQuePaso(tester);
        await a.elegir(tester, OpcionQuePaso.entrevistaDada);
        await tester.tap(find.textContaining('Ana'));
        await a.asentar(tester);
        await tester.tap(find.text('Empezar entrevista'));
        await a.asentar(tester);

        // Lo que se espera: o la entrevista es con Ana, o un aviso dice que ya hay una con Pedro.
        final conAna = a.montaje.almacen.guardadas['col-1']!.espacioPersonaId == 'ep-2';
        final avisa = find.textContaining('Ya tenés una entrevista en curso').evaluate().isNotEmpty;
        expect(
          conAna || avisa,
          isTrue,
          reason:
              'el gancho recibió ${a.entrevistas.single.persona!.espacioPersonaId} y la entrevista '
              'en curso quedó con ${a.montaje.almacen.guardadas['col-1']!.espacioPersonaId}',
        );
      },
    );

    testWidgets('volver atrás desde «Vender» sin guardar no avisa y deja «¿Qué pasó?» como estaba', (
      tester,
    ) async {
      final a = Arnes648();
      a.lector.porVinculo['ep-1'] = ayer648;
      await a.montar(tester, tamano: t360x640);
      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.vender);
      await a.tocarKey(tester, const Key('venta_atras'));

      // QA de #648 P1 (decisión de #661): ningún aviso, ni tapado detrás de la hoja ni a la vista.
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('La venta no se guardó'), findsNothing);
      expect(find.byKey(ClavesQuePaso.falla), findsNothing);
      expect(_hojaQuePaso, findsOneWidget);
      expect(_vender, findsOneWidget);
      expect(a.entorno.ventas.recibidas, isEmpty);
    });
  });
}
