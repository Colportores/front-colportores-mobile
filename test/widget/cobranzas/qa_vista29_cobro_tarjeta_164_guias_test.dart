// Guías de accesibilidad de Flutter sobre cada estado de «Cobro con tarjeta y por transferencia»
// (vista 29, #164), en 360x640 y 412x915, con texto 1,0 y 2,0. Va aparte del resto del QA: la guía de
// contraste lee los colores de la captura y con las fuentes reales da falsos negativos (con las cajas
// de Ahem lee el color de verdad).

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista29_164_arnes.dart';

void main() {
  sinFuentesReales164();

  for (final tamano in [chico164, grande164]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in Estado164.values) {
        group('${estado.rotulo} · ${sufijo164(tamano, escala)}', () {
          Future<void> verificar(WidgetTester tester, AccessibilityGuideline guia) async {
            final h = tester.ensureSemantics();
            final a = await llegarA164(tester, estado, tamano: tamano, escala: escala);
            await expectLater(tester, meetsGuideline(guia));
            await liberar164(tester, a);
            h.dispose();
          }

          testWidgets(
            'tamaño de toque Android (48 dp)',
            (t) => verificar(t, androidTapTargetGuideline),
          );
          testWidgets('tamaño de toque iOS (44 pt)', (t) => verificar(t, iOSTapTargetGuideline));
          testWidgets(
            'todo lo tocable tiene nombre',
            (t) => verificar(t, labeledTapTargetGuideline),
          );
          testWidgets('contraste del texto', (t) => verificar(t, textContrastGuideline));
        });
      }
    }
  }
}
