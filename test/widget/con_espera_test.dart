// "Iniciando…" / "Finalizando…" (vista 21A·04): la etiqueta de un botón que está trabajando se lee.
//
// El botón queda apagado mientras trabaja y Material lo pinta con texto gris al 38 %, que sobre el
// azul daba ~1.9:1. `ConEspera.estiloDelBoton` lo deja como el canvas: `onPrimary` sobre `primary`
// al 85 % y el círculo del mismo color que la etiqueta.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/jornada/presentation/widgets/con_espera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';

double _contraste(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (claro, oscuro) = la >= lb ? (la, lb) : (lb, la);
  return (claro + 0.05) / (oscuro + 0.05);
}

Future<void> _montar(WidgetTester tester, {required bool trabajando, double escala = 1}) {
  final tema = temaClaro();
  return tester.pumpWidget(
    MaterialApp(
      theme: tema,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => FilledButton(
              key: const Key('boton'),
              onPressed: trabajando ? null : () {},
              style: trabajando ? ConEspera.estiloDelBoton(context) : null,
              child: trabajando ? const ConEspera('Finalizando…') : const Text('Finalizar'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  final tema = temaClaro();
  final esquema = tema.colorScheme;

  group('Botón que está trabajando', () {
    testWidgets('la etiqueta va en onPrimary sobre primary al 85 % y se lee (WCAG 1.4.3)', (
      tester,
    ) async {
      await _montar(tester, trabajando: true);
      // La transición del botón apagado dura 200 ms: se mide ya terminada.
      await tester.pump(const Duration(seconds: 1));

      final etiqueta = find.text('Finalizando…');
      final color = tester.renderObject<RenderParagraph>(etiqueta).text.style!.color!;
      expect(color, esquema.onPrimary);

      final material = tester.widget<Material>(
        find.descendant(of: find.byKey(const Key('boton')), matching: find.byType(Material)).first,
      );
      expect(material.color, esquema.primary.withValues(alpha: .85));

      final fondo = Color.alphaBlend(material.color!, tema.scaffoldBackgroundColor);
      expect(_contraste(color, fondo), greaterThanOrEqualTo(4.5));
    });

    testWidgets('el círculo va del mismo color que la etiqueta', (tester) async {
      await _montar(tester, trabajando: true);
      await tester.pump(const Duration(seconds: 1));

      final aro = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(aro.color, esquema.onPrimary);
      expect(aro.backgroundColor, esquema.onPrimary.withValues(alpha: .35));
    });

    testWidgets('el botón sigue apagado: no admite otro toque', (tester) async {
      await _montar(tester, trabajando: true);

      expect(tester.widget<FilledButton>(find.byKey(const Key('boton'))).onPressed, isNull);
    });

    testWidgets('con el texto al 200 % la etiqueta sigue legible y sin overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _montar(tester, trabajando: true, escala: 2);
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      final color = tester
          .renderObject<RenderParagraph>(find.text('Finalizando…'))
          .text
          .style!
          .color!;
      expect(color, esquema.onPrimary);
    });
  });

  testWidgets('sin trabajar, el botón conserva el estilo normal del tema', (tester) async {
    await _montar(tester, trabajando: false);
    await tester.pump(const Duration(seconds: 1));

    final color = tester.renderObject<RenderParagraph>(find.text('Finalizar')).text.style!.color!;
    expect(color, esquema.onPrimary);
    final material = tester.widget<Material>(
      find.descendant(of: find.byKey(const Key('boton')), matching: find.byType(Material)).first,
    );
    expect(material.color, esquema.primary);
  });
}
