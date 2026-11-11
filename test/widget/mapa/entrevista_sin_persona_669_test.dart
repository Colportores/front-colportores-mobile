// «Entrevista dada» sin saber con quién (vista 39; #669, casillas 1 y 5 de #661): la decisión de Cristian
// del 05/11, «Entrev. s/n» («Empieza sin nombre»). La entrevista en curso admite no tener persona; la
// visita que se guarda al terminar queda de la casa, sin persona; y si en R·06 hay venta, se pide el
// nombre con el alta corta (32 A) antes de la venta. Con los ganchos enchufados a los flujos reales,
// como los enchufa `main.dart`.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart'
    show TipoResultadoVisita;
import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_personas.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_con_quien.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show casaMataojo;
import '../../helpers/entrevista_dada_648_arnes.dart';
import '../../helpers/persona_falsos.dart';

Finder get _ventaPagina => find.byKey(const Key('nueva_venta_pagina'));
Finder get _alta => find.byType(AltaPersonaPage);
Finder get _botonGuardarPersona => find.widgetWithText(FilledButton, TextosPersonas.guardar);
Finder get _campoNombre => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == TextosPersonas.sugerenciaNombre,
);

PersonaRepositorioFalso _personas(Arnes648 a, WidgetTester tester) =>
    a.contenedor(tester).read(personaRepositoryProvider) as PersonaRepositorioFalso;

/// Una casa sin personas, «Entrevista dada» → «Todavía no sé con quién» → R·05.
Future<void> _hastaR05(WidgetTester tester, Arnes648 a, {double escala = 1}) async {
  await a.montar(tester, personas: [], escala: escala);
  a.montaje.rotulo = (direccion: 'Grecia 3307', persona: '');
  await a.abrirQuePaso(tester);
  await a.elegir(tester, OpcionQuePaso.entrevistaDada);
  await a.tocarKey(tester, ClavesConQuien.todaviaNoSe);
}

/// Hasta R·06 «¿Hubo venta?».
Future<void> _hastaR06(WidgetTester tester, Arnes648 a, {double escala = 1}) async {
  await _hastaR05(tester, a, escala: escala);
  await a.tocarKey(tester, ClavesEntrevista.finalizar);
}

Future<void> _escribirNombre(WidgetTester tester, String nombre) async {
  await tester.enterText(_campoNombre, nombre);
  await tester.pump();
}

Future<void> _guardarPersona(WidgetTester tester, Arnes648 a) async {
  await tester.ensureVisible(_botonGuardarPersona);
  await tester.pump();
  await tester.tap(_botonGuardarPersona);
  await a.asentar(tester);
}

void main() {
  late Arnes648 a;

  setUp(() => a = Arnes648());

  group('empieza sin nombre', () {
    testWidgets('«Todavía no sé con quién» empieza la entrevista colgada de la casa, sin persona', (
      tester,
    ) async {
      await _hastaR05(tester, a);

      expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsOneWidget);
      final guardada = a.montaje.almacen.guardadas['col-1']!;
      expect(guardada.espacioId, 'esp-1');
      expect(guardada.espacioPersonaId, isNull, reason: 'no se inventa a nadie');
      expect(guardada.inicio.isAtSameMomentAs(a.montaje.reloj()), isTrue);
      expect(a.entrevistas.single.persona, isNull);
      expect(_personas(a, tester).recibidas, isEmpty, reason: 'no se guarda a nadie');
      expect(a.resultados, isEmpty, reason: '«¿Qué pasó?» espera a que R·05 se resuelva');
    });

    testWidgets('cerrar R·05 la deja en curso, sin persona: aviso fijo en el mapa', (tester) async {
      await _hastaR05(tester, a);

      await tester.binding.handlePopRoute();
      await a.asentar(tester);

      expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);
      expect(a.montaje.almacen.guardadas['col-1']!.espacioPersonaId, isNull);
      expect(a.resultados, [true]);
    });

    testWidgets('R·06 sin venta: «No, guardar y volver al mapa» guarda la visita sin persona', (
      tester,
    ) async {
      await _hastaR06(tester, a);

      expect(find.byKey(ClavesEntrevista.hojaTermino), findsOneWidget);
      await a.tocarKey(tester, ClavesEntrevista.guardarYVolver);

      final visita = a.montaje.agenda.recibidas.single.visita;
      expect(visita.tipoResultado, TipoResultadoVisita.entrevista);
      expect(visita.espacioId, 'esp-1');
      expect(visita.espacioPersonaId, isNull, reason: 'la visita sube sin persona');
      expect(a.montaje.almacen.guardadas, isEmpty);
      expect(find.byKey(ClavesEntrevista.avisoFijo), findsNothing);
      expect(_alta, findsNothing, reason: 'sin venta no se pide el nombre');
      expect(_personas(a, tester).recibidas, isEmpty);
      expect(a.resultados, [true]);
      expect(a.entorno.ventas.recibidas, isEmpty);
    });

    testWidgets(
      'si el guardado falla, el botón vuelve a habilitarse y se reintenta con los mismos ids',
      (tester) async {
        await _hastaR06(tester, a);
        a.montaje.agenda.falla = const FailureInesperado();

        await a.tocarKey(tester, ClavesEntrevista.guardarYVolver);

        expect(find.byKey(ClavesEntrevista.avisoError), findsOneWidget);
        expect(a.montaje.almacen.guardadas, hasLength(1), reason: 'la entrevista sigue en curso');

        a.montaje.agenda.falla = null;
        await a.tocarKey(tester, ClavesEntrevista.guardarYVolver);

        expect(a.montaje.agenda.recibidas.single.visita.espacioPersonaId, isNull);
        expect(a.montaje.almacen.guardadas, isEmpty);
      },
    );

    testWidgets('si «Empezar» no se pudo guardar, sigue R·07 y también queda sin persona', (
      tester,
    ) async {
      await a.montar(tester, personas: []);
      a.montaje.rotulo = (direccion: 'Grecia 3307', persona: '');
      a.montaje.rota.fallaAlGuardar = true;
      a.montaje.ultimaVisita.fecha = DateTime(2026, 10, 23, 14, 5);
      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.entrevistaDada);
      await a.tocarKey(tester, ClavesConQuien.todaviaNoSe);

      expect(find.byKey(ClavesEntrevista.hojaTermino), findsOneWidget);
      expect(find.byKey(ClavesEntrevista.avisoSinInicio), findsOneWidget);
      await a.tocarKey(tester, ClavesEntrevista.guardarYVolver);

      final visita = a.montaje.agenda.recibidas.single.visita;
      expect(visita.tipoResultado, TipoResultadoVisita.entrevista);
      expect(visita.espacioPersonaId, isNull);
      expect(a.montaje.almacen.guardadas, isEmpty);
    });
  });

  group('con venta: se pide el nombre con el alta corta (32 A) antes de la venta', () {
    testWidgets('el alta dice para qué se pide el nombre: solo en este paso (#672, QA)', (
      tester,
    ) async {
      await _hastaR06(tester, a);

      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);

      expect(_alta, findsOneWidget);
      expect(find.byKey(ClavesAltaPersona.ayuda), findsOneWidget);
      expect(
        find.text('Para registrar la venta, anotá a quién se la hacés. Con el nombre alcanza.'),
        findsOneWidget,
      );
    });

    testWidgets('el alta de siempre (pestaña Personas) no lleva esa línea', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            personaRepositoryProvider.overrideWithValue(PersonaRepositorioFalso()),
            espacioRepositoryProvider.overrideWithValue(
              EspacioRepositorioParaPersonas(casaMataojo()),
            ),
          ],
          child: const MaterialApp(
            home: AltaPersonaPage(espacioId: 'esp-1', colportorId: 'col-1'),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(ClavesAltaPersona.ayuda), findsNothing);
      expect(find.text(TextosPersonas.altaTitulo), findsOneWidget);
    });

    testWidgets(
      '«Sí, registrar la venta» abre el alta; con el nombre, la venta queda a su nombre',
      (tester) async {
        await _hastaR06(tester, a);

        await a.tocarKey(tester, ClavesEntrevista.registrarVenta);

        expect(_alta, findsOneWidget, reason: 'sin nadie a quien vender, primero el nombre');
        expect(_ventaPagina, findsNothing);
        expect(a.montaje.agenda.recibidas, isEmpty, reason: 'R44: nada se guarda hasta la venta');

        await _escribirNombre(tester, 'Lucía');
        await _guardarPersona(tester, a);

        expect(_alta, findsNothing);
        expect(_ventaPagina, findsOneWidget);
        expect(
          find.text('Lucía'),
          findsOneWidget,
          reason: 'la venta es de la persona recién anotada',
        );
        final alta = _personas(a, tester).recibidas.single;
        expect(alta.persona.nombre, 'Lucía');
        expect(alta.vinculo.espacioId, 'esp-1');

        await a.armarLaVenta(tester);
        await a.registrarSinFecha(tester);

        final visita = a.montaje.agenda.recibidas.single.visita;
        expect(visita.tipoResultado, TipoResultadoVisita.venta);
        expect(visita.espacioPersonaId, alta.vinculo.id);
        final venta = a.entorno.ventas.recibidas.single.venta;
        expect(venta.espacioPersonaId, alta.vinculo.id);
        expect(venta.visitaId, visita.id);
        expect(a.montaje.almacen.guardadas, isEmpty, reason: 'la entrevista se cerró con la venta');
        expect(a.salidasDeEntrevista.single, isA<VentaRegistradaEnLaCasa>());
        expect(a.resultados, [true], reason: 'tras guardar (05/11): la hoja de la casa se cierra');
      },
    );

    testWidgets('atrás desde el alta vuelve a R·06 sin perder la entrevista ni guardar a nadie', (
      tester,
    ) async {
      await _hastaR06(tester, a);
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
      expect(_alta, findsOneWidget);

      await tester.binding.handlePopRoute();
      await a.asentar(tester);

      expect(_alta, findsNothing);
      expect(
        find.byKey(ClavesEntrevista.hojaTermino),
        findsOneWidget,
        reason: 'un paso atrás: R·06',
      );
      expect(find.byKey(ClavesEntrevista.registrarVenta), findsOneWidget);
      expect(a.montaje.almacen.guardadas['col-1']!.espacioPersonaId, isNull);
      expect(_personas(a, tester).recibidas, isEmpty);
      expect(a.montaje.agenda.recibidas, isEmpty);
      expect(a.entorno.ventas.recibidas, isEmpty);
      expect(a.resultados, isEmpty, reason: '«¿Qué pasó?» sigue esperando');

      // Se puede elegir otra salida de R·06: guardar sin venta, sin persona.
      await a.tocarKey(tester, ClavesEntrevista.guardarYVolver);
      expect(a.montaje.agenda.recibidas.single.visita.espacioPersonaId, isNull);
      expect(a.montaje.almacen.guardadas, isEmpty);
    });

    testWidgets('atrás desde el alta y reentrar: el nombre se pide de nuevo y la venta sigue', (
      tester,
    ) async {
      await _hastaR06(tester, a);
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
      await tester.binding.handlePopRoute();
      await a.asentar(tester);

      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
      expect(_alta, findsOneWidget);
      await _escribirNombre(tester, 'Lucía');
      await _guardarPersona(tester, a);

      expect(_ventaPagina, findsOneWidget);
      expect(_personas(a, tester).recibidas, hasLength(1));
    });

    testWidgets('si el alta falla a mitad, nada queda trabado: el botón dice «Reintentar»', (
      tester,
    ) async {
      await _hastaR06(tester, a);
      _personas(a, tester).resultados.add(const FailureInesperado());
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
      await _escribirNombre(tester, 'Lucía');

      await _guardarPersona(tester, a);

      expect(_alta, findsOneWidget);
      expect(find.text(TextosPersonas.noPudimosGuardar), findsOneWidget);
      expect(_ventaPagina, findsNothing);
      expect(find.text(TextosPersonas.reintentar), findsWidgets);

      await tester.tap(find.text(TextosPersonas.reintentar).last);
      await a.asentar(tester);

      expect(_ventaPagina, findsOneWidget);
      // Los mismos ids en el reintento: una sola persona.
      expect(_personas(a, tester).recibidas.map((r) => r.persona.id).toSet(), hasLength(1));
    });

    testWidgets('doble toque en «Guardar persona»: una sola persona y una sola venta abierta', (
      tester,
    ) async {
      await _hastaR06(tester, a);
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
      await _escribirNombre(tester, 'Lucía');

      await tester.ensureVisible(_botonGuardarPersona);
      await tester.pump();
      await tester.tap(_botonGuardarPersona);
      await tester.tap(_botonGuardarPersona, warnIfMissed: false);
      await a.asentar(tester);

      expect(_personas(a, tester).recibidas, hasLength(1));
      expect(_ventaPagina, findsOneWidget);
    });

    testWidgets(
      'si la venta no se completa tras el alta, la entrevista sigue con la persona y no se vuelve a pedir',
      (tester) async {
        await _hastaR06(tester, a);
        await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
        await _escribirNombre(tester, 'Lucía');
        await _guardarPersona(tester, a);
        final vinculo = _personas(a, tester).recibidas.single.vinculo.id;

        await a.tocarKey(tester, const Key('venta_atras'));

        // R44: ni visita ni venta; la entrevista sigue en curso, ahora con la persona que se anotó.
        expect(a.montaje.agenda.recibidas, isEmpty);
        expect(a.entorno.ventas.recibidas, isEmpty);
        expect(a.montaje.almacen.guardadas['col-1']!.espacioPersonaId, vinculo);
        expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);

        // Se vuelve a la entrevista y a la venta: ya no se pide el nombre ni se da de alta otra vez.
        await a.tocarKey(tester, ClavesEntrevista.avisoFijo);
        await a.tocarKey(tester, ClavesEntrevista.finalizar);
        await a.tocarKey(tester, ClavesEntrevista.registrarVenta);

        expect(_alta, findsNothing);
        expect(_ventaPagina, findsOneWidget);
        expect(find.text('Lucía'), findsOneWidget);
        await a.armarLaVenta(tester);
        await a.registrarSinFecha(tester);

        expect(_personas(a, tester).recibidas, hasLength(1));
        expect(a.montaje.agenda.recibidas.single.visita.espacioPersonaId, vinculo);
        expect(a.entorno.ventas.recibidas.single.venta.espacioPersonaId, vinculo);
      },
    );

    testWidgets(
      'si la visita de la venta no se guarda, la venta tampoco y se reintenta con la misma persona',
      (tester) async {
        await _hastaR06(tester, a);
        await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
        await _escribirNombre(tester, 'Lucía');
        await _guardarPersona(tester, a);
        await a.armarLaVenta(tester);
        a.montaje.agenda.falla = const FailureInesperado();

        await a.tocarKey(tester, const Key('venta_cta'));

        expect(_ventaPagina, findsOneWidget);
        expect(a.salidasDeEntrevista, isEmpty);
        expect(a.montaje.agenda.recibidas, isEmpty);

        a.montaje.agenda.falla = null;
        await a.registrarSinFecha(tester);

        expect(a.montaje.agenda.recibidas, hasLength(1));
        expect(_personas(a, tester).recibidas, hasLength(1));
        expect(a.salidasDeEntrevista.single, isA<VentaRegistradaEnLaCasa>());
      },
    );

    testWidgets('si «Empezar» no se pudo guardar (R·07) y hay venta, también pide el nombre', (
      tester,
    ) async {
      await a.montar(tester, personas: []);
      a.montaje.rotulo = (direccion: 'Grecia 3307', persona: '');
      a.montaje.rota.fallaAlGuardar = true;
      a.montaje.ultimaVisita.fecha = DateTime(2026, 10, 23, 14, 5);
      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.entrevistaDada);
      await a.tocarKey(tester, ClavesConQuien.todaviaNoSe);

      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
      expect(_alta, findsOneWidget);
      await _escribirNombre(tester, 'Lucía');
      await _guardarPersona(tester, a);
      expect(_ventaPagina, findsOneWidget);
      await a.armarLaVenta(tester);
      await a.registrarSinFecha(tester);

      final alta = _personas(a, tester).recibidas.single;
      final visita = a.montaje.agenda.recibidas.single.visita;
      expect(visita.tipoResultado, TipoResultadoVisita.venta);
      expect(visita.espacioPersonaId, alta.vinculo.id);
      expect(a.entorno.ventas.recibidas.single.venta.espacioPersonaId, alta.vinculo.id);
    });

    testWidgets('R·07 con venta: atrás desde el alta vuelve a R·07', (tester) async {
      await a.montar(tester, personas: []);
      a.montaje.rotulo = (direccion: 'Grecia 3307', persona: '');
      a.montaje.rota.fallaAlGuardar = true;
      a.montaje.ultimaVisita.fecha = DateTime(2026, 10, 23, 14, 5);
      await a.abrirQuePaso(tester);
      await a.elegir(tester, OpcionQuePaso.entrevistaDada);
      await a.tocarKey(tester, ClavesConQuien.todaviaNoSe);
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
      expect(_alta, findsOneWidget);

      await tester.binding.handlePopRoute();
      await a.asentar(tester);

      expect(find.byKey(ClavesEntrevista.hojaTermino), findsOneWidget);
      expect(find.byKey(ClavesEntrevista.avisoSinInicio), findsOneWidget);
      expect(_personas(a, tester).recibidas, isEmpty);
      expect(a.montaje.agenda.recibidas, isEmpty);
    });
  });

  group('datos límite', () {
    testWidgets('textScaler 2.0: el alta antes de la venta se ve y se toca sin desbordar', (
      tester,
    ) async {
      await _hastaR06(tester, a, escala: 2);
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);

      expect(_alta, findsOneWidget);
      await _escribirNombre(tester, 'Lucía');
      await _guardarPersona(tester, a);

      expect(tester.takeException(), isNull);
      expect(_ventaPagina, findsOneWidget);
    });

    testWidgets('un nombre largo y con acentos se guarda tal cual', (tester) async {
      await _hastaR06(tester, a);
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
      const largo = 'Ñandú Bartolomé Josefina de los Ángeles Pérez';
      await _escribirNombre(tester, largo);
      await _guardarPersona(tester, a);

      expect(_personas(a, tester).recibidas.single.persona.nombre, largo);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'el texto «Sin nombre» no aparece en R·05 ni en R·06 de una entrevista sin persona',
      (tester) async {
        await _hastaR06(tester, a);

        expect(find.text(TextosEntrevista.sinNombre), findsNothing);
      },
    );
  });

  group('con una entrevista sin persona en curso', () {
    testWidgets(
      'otra «Entrevista dada» en la misma casa con persona no pisa la que está en curso',
      (tester) async {
        await a.montar(tester);
        a.montaje.rotulo = (direccion: 'Grecia 3307', persona: '');
        await a
            .contenedor(tester)
            .read(entrevistaEnCursoProvider('col-1').notifier)
            .empezar(espacioId: 'esp-1');
        await a.asentar(tester);

        await a.abrirQuePaso(tester);
        await a.elegir(tester, OpcionQuePaso.entrevistaDada);

        // Ya hay una en curso en esta casa, sin persona: se dice y no se empieza otra encima.
        expect(find.text(TextosEntrevista.yaHayUnaEnCurso('Grecia 3307')), findsOneWidget);
        expect(a.montaje.almacen.guardadas['col-1']!.espacioPersonaId, isNull);
        expect(a.montaje.almacen.guardadas, hasLength(1));
      },
    );
  });
}
