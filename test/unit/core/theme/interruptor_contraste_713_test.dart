// El interruptor apagado se distingue de su fondo (WCAG 1.4.11, 3:1 para un componente): decisión del
// 17/11, P2 del QA de #715. El tema pinta el borde y el pulgar del apagado con el `gris` de la paleta;
// encendido y deshabilitado quedan como los dibuja Material.
import 'dart:math' as math;

import 'package:colportores_mobile/core/theme/colores_colportaje.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _luminancia(Color c) {
  double canal(double v) => v <= .03928 ? v / 12.92 : math.pow((v + .055) / 1.055, 2.4).toDouble();
  return .2126 * canal(c.r) + .7152 * canal(c.g) + .0722 * canal(c.b);
}

double _contraste(Color a, Color b) {
  final la = _luminancia(a);
  final lb = _luminancia(b);
  return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
}

void main() {
  final tema = temaClaro().switchTheme;
  const apagado = <WidgetState>{};

  test(
    'apagado: borde y pulgar en el gris de la paleta, a 3:1 o más contra el blanco y el crema',
    () {
      final borde = tema.trackOutlineColor!.resolve(apagado)!;
      final pulgar = tema.thumbColor!.resolve(apagado)!;

      expect(borde, ColoresColportaje.unica.gris);
      expect(pulgar, ColoresColportaje.unica.gris);
      for (final fondo in [Colors.white, temaClaro().colorScheme.surface]) {
        expect(_contraste(borde, fondo), greaterThanOrEqualTo(3), reason: '$fondo');
        expect(_contraste(pulgar, fondo), greaterThanOrEqualTo(3), reason: '$fondo');
      }
    },
  );

  test('encendido y deshabilitado: lo de Material (el tema no los toca)', () {
    for (final estados in [
      {WidgetState.selected},
      {WidgetState.disabled},
      {WidgetState.selected, WidgetState.disabled},
    ]) {
      expect(tema.thumbColor!.resolve(estados), isNull, reason: '$estados');
      expect(tema.trackOutlineColor!.resolve(estados), isNull, reason: '$estados');
    }
  });

  testWidgets('un interruptor apagado de la app se dibuja con ese borde', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: temaClaro(),
        home: const Scaffold(
          body: Center(child: Switch(value: false, onChanged: _nada)),
        ),
      ),
    );

    final efectivo = Theme.of(tester.element(find.byType(Switch))).switchTheme;
    expect(efectivo.trackOutlineColor!.resolve(apagado), ColoresColportaje.unica.gris);
  });
}

void _nada(bool _) {}
