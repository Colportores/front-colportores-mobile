// QA de la entrevista sin persona y de «Vender» con su visita (vista 39 R·04 → R·08, C·06 / C·07 y el alta
// corta 32 A pedida antes de la venta; #669, PR #672): cada estado nuevo en 360×640 y 412×915 a texto 1,0 y
// 2,0 (sin desborde, sin textos huérfanos), el alta con entradas hostiles, las acciones superpuestas y los
// avisos. Con fuentes reales; las guías de accesibilidad van aparte (`..._guias_test.dart`).
//
// Los hallazgos van con `skip` (`--dart-define=QA_HALLAZGOS=true` los corre). Las capturas, con
// `--dart-define=QA_CAPTURAS=true`, van a `.dart_tool/qa_capturas/` (nunca se commitean).
import 'package:colportores_mobile/features/agenda/presentation/providers/entrevista_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/textos_entrevista.dart';
import 'package:colportores_mobile/features/mapa/presentation/textos_personas.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_669_arnes.dart';

/// Todos los textos que se ven en pantalla.
List<String> _textos(WidgetTester tester) => [
  for (final w in tester.widgetList<Text>(find.byType(Text)))
    if (w.data != null) w.data! else if (w.textSpan != null) w.textSpan!.toPlainText(),
];

void main() {
  group('matriz de estados nuevos × tamaños × escala de texto', () {
    for (final tamano in [t360x640, t412x915]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in Estado669.values) {
          testWidgets(
            '${estado.name} · ${sufijo669(tamano, escala)}: sin desborde ni textos huérfanos',
            (tester) async {
              await llegarA669(tester, estado, tamano: tamano, escala: escala);
              await tester.pump(const Duration(milliseconds: 400));

              expect(tester.takeException(), isNull, reason: 'overflow o excepción de render');
              final textos = _textos(tester);
              for (final t in textos) {
                expect(t.contains('null'), isFalse, reason: 'se coló un null: «$t»');
                expect(t.trim().endsWith('·'), isFalse, reason: 'separador huérfano: «$t»');
                expect(t.trim().startsWith('·'), isFalse, reason: 'separador huérfano: «$t»');
              }
              await capturar669(tester, '${estado.name}_${sufijo669(tamano, escala)}');
            },
          );
        }
      }
    }
  });

  group('estados: contenido y salida', () {
    testWidgets('R·05 sin persona: la hoja dice la dirección y no inventa un nombre', (
      tester,
    ) async {
      await llegarA669(tester, Estado669.r05SinPersona);

      expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsOneWidget);
      expect(find.textContaining('Grecia 3307'), findsWidgets);
      expect(find.text('Sin nombre'), findsNothing);
    });

    testWidgets('el aviso fijo de una entrevista sin persona se puede tocar y reabre R·05', (
      tester,
    ) async {
      final a = await llegarA669(tester, Estado669.avisoFijoSinPersona);

      expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);
      await a.tocarKey(tester, ClavesEntrevista.avisoFijo);
      expect(find.byKey(ClavesEntrevista.hojaEnCurso), findsOneWidget);
    });

    testWidgets('R·06 sin persona con falla: el aviso dice qué hacer y los botones siguen vivos', (
      tester,
    ) async {
      final a = await llegarA669(tester, Estado669.r06SinPersonaNoSeGuardo);

      expect(find.byKey(ClavesEntrevista.avisoError), findsOneWidget);
      final boton = find.byKey(ClavesEntrevista.guardarYVolver);
      final guardar = tester.widget<ButtonStyleButton>(
        find
                .ancestor(
                  of: boton,
                  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
                )
                .evaluate()
                .isNotEmpty
            ? find.ancestor(
                of: boton,
                matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
              )
            : boton,
      );
      expect(guardar.onPressed, isNotNull, reason: 'el botón no queda trabado tras la falla');
      a.montaje.agenda.falla = null;
      await a.tocarKey(tester, ClavesEntrevista.guardarYVolver);
      expect(a.montaje.agenda.recibidas, hasLength(1));
    });

    testWidgets('R·07 sin persona: avisa que no hubo inicio y deja pedir el nombre si hay venta', (
      tester,
    ) async {
      final a = await llegarA669(tester, Estado669.r07SinPersona);

      expect(find.byKey(ClavesEntrevista.avisoSinInicio), findsOneWidget);
      await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
      expect(altaPagina669, findsOneWidget);
    });

    testWidgets(
      '«Vender» con la persona dada de baja: el aviso dice qué hacer y queda a la vista',
      (tester) async {
        await llegarA669(tester, Estado669.venderPersonaDeBaja);

        expect(find.textContaining('Elegí otra opción'), findsOneWidget);
        expect(find.byKey(ClavesQuePaso.opcion(OpcionQuePaso.vender)), findsOneWidget);
      },
    );

    testWidgets('«Vender» sin nadie entrevistada: el aviso fijo de la hoja dice qué hacer', (
      tester,
    ) async {
      await llegarA669(tester, Estado669.venderSinNadie);

      expect(
        find.text('Ya no queda ninguna persona entrevistada en esta casa. Elegí otra opción.'),
        findsOneWidget,
      );
      expect(find.byKey(ClavesQuePaso.guardando), findsNothing);
    });
  });

  group('el alta (32 A) pedida antes de la venta: entradas hostiles', () {
    testWidgets(
      'nombre vacío: no se guarda, el error dice qué hacer y no se pierde la entrevista',
      (tester) async {
        final a = await llegarA669(tester, Estado669.altaConErrorDeNombre);

        expect(altaPagina669, findsOneWidget);
        expect(personas669(a, tester).recibidas, isEmpty);
        expect(a.montaje.almacen.guardadas['col-1'], isNotNull);
        expect(ventaPagina669, findsNothing);
      },
    );

    testWidgets('solo espacios: no se guarda', (tester) async {
      final a = await llegarA669(tester, Estado669.altaDesdeR06);

      await escribirNombre669(tester, '     ');
      await guardarPersona669(tester, a);

      expect(personas669(a, tester).recibidas, isEmpty);
      expect(altaPagina669, findsOneWidget);
    });

    testWidgets('nombre con emoji y caracteres especiales: se guarda tal cual y sigue la venta', (
      tester,
    ) async {
      final a = await llegarA669(tester, Estado669.altaDesdeR06);

      await escribirNombre669(tester, "Zoë O'Brien-Núñez 🙂");
      await guardarPersona669(tester, a);

      expect(tester.takeException(), isNull);
      expect(personas669(a, tester).recibidas, hasLength(1));
      expect(ventaPagina669, findsOneWidget);
    });

    testWidgets('texto pegado de 500 caracteres: se recorta al tope y no desborda', (tester) async {
      final a = await llegarA669(tester, Estado669.altaDesdeR06, escala: 2);

      await escribirNombre669(tester, 'M' * 500);
      await guardarPersona669(tester, a);

      expect(tester.takeException(), isNull);
      final alta = personas669(a, tester).recibidas;
      expect(alta, hasLength(1));
      expect(alta.single.persona.nombre.length, lessThanOrEqualTo(60));
    });

    testWidgets('tras la falla lo tipeado no se pierde y «Reintentar» guarda a una sola persona', (
      tester,
    ) async {
      final a = await llegarA669(tester, Estado669.altaConFalla);

      expect(find.text(TextosPersonas.noPudimosGuardar), findsOneWidget);
      final campo = tester.widget<TextField>(campoNombre669);
      expect(campo.controller!.text, 'Lucía');
      expect(campo.enabled, isNot(false), reason: 'el campo no queda bloqueado tras la falla');

      await tester.tap(find.text(TextosPersonas.reintentar).last);
      await a.asentar(tester);
      expect(ventaPagina669, findsOneWidget);
      expect(personas669(a, tester).recibidas.map((r) => r.persona.id).toSet(), hasLength(1));
    });
  });

  group('acciones superpuestas y reentrada', () {
    testWidgets('dos toques seguidos en «Sí, registrar la venta»: una sola alta abierta', (
      tester,
    ) async {
      final a = await llegarA669(tester, Estado669.r06SinPersona);

      await tester.ensureVisible(find.byKey(ClavesEntrevista.registrarVenta));
      await tester.tap(find.byKey(ClavesEntrevista.registrarVenta));
      await tester.tap(find.byKey(ClavesEntrevista.registrarVenta), warnIfMissed: false);
      await a.asentar(tester);

      expect(altaPagina669, findsOneWidget);
      await tester.binding.handlePopRoute();
      await a.asentar(tester);
      expect(altaPagina669, findsNothing);
      expect(
        find.byKey(ClavesEntrevista.hojaTermino),
        findsOneWidget,
        reason: 'un paso atrás: R·06',
      );
    });

    testWidgets('el alta se abre, se vuelve atrás tres veces y se reentra: nada se duplica', (
      tester,
    ) async {
      final a = await llegarA669(tester, Estado669.r06SinPersona);

      for (var i = 0; i < 3; i++) {
        await a.tocarKey(tester, ClavesEntrevista.registrarVenta);
        expect(altaPagina669, findsOneWidget);
        await tester.binding.handlePopRoute();
        await a.asentar(tester);
      }
      expect(personas669(a, tester).recibidas, isEmpty);
      expect(a.montaje.agenda.recibidas, isEmpty);
      expect(a.montaje.almacen.guardadas['col-1'], isNotNull);
    });

    testWidgets(
      'persona anotada y venta abandonada: el aviso nombra a la persona y dice qué hacer',
      (tester) async {
        await llegarA669(tester, Estado669.ventaTrasElAltaNoGuardada);

        expect(
          find.text('La venta no se guardó. La entrevista con Lucía sigue en curso.'),
          findsOneWidget,
        );
        expect(find.byKey(ClavesEntrevista.avisoFijo), findsOneWidget);
      },
    );

    testWidgets(
      'R·07: tras anotar a la persona y salir de la venta, el aviso no dice «sigue en curso» '
      'si no hay ninguna entrevista en curso',
      (tester) async {
        final a = await llegarA669(tester, Estado669.altaDesdeR07);
        await escribirNombre669(tester, 'Lucía');
        await guardarPersona669(tester, a);
        await a.tocarKey(tester, const Key('venta_atras'));

        expect(a.montaje.almacen.guardadas, isEmpty, reason: 'en R·07 no hay entrevista en curso');
        expect(
          find.textContaining('sigue en curso'),
          findsNothing,
          reason: 'el aviso afirma una entrevista en curso que no existe (no hay a dónde ir)',
        );
      },
      // skip: QA #669 — R·07 + alta + salir de la venta: «La entrevista con Lucía sigue en curso» sin entrevista.
      skip: !verHallazgos669,
    );
  });

  group('«Vender» con su visita: texto y recorrido', () {
    testWidgets('la venta de «Vender» abre en 360×640 a 2× sin desborde', (tester) async {
      final a = await llegarA669(tester, Estado669.venderLaVenta, escala: 2);

      expect(tester.takeException(), isNull);
      expect(ventaPagina669, findsOneWidget);
      expect(a.montaje.agenda.recibidas, isEmpty);
    });

    testWidgets('el aviso de la casa dada de baja nombra qué pasó y qué hacer', (tester) async {
      await llegarA669(tester, Estado669.venderCasaDeBaja);

      expect(
        find.text(
          'La venta no se guardó. La casa ya no está en tu teléfono, así que no se puede '
          'registrar la venta. Elegí otra opción.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'los textos de privacidad: la entrevista en curso sin persona no imprime ids ni nombres',
      (tester) async {
        final a = await llegarA669(tester, Estado669.r05SinPersona);
        final enCurso = a.contenedor(tester).read(entrevistaEnCursoProvider('col-1')).entrevista!;

        expect(enCurso.toString(), isNot(contains('Lucía')));
        expect(enCurso.espacioPersonaId, isNull);
      },
    );
  });
}
