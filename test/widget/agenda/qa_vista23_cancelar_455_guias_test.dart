// Guías de accesibilidad de Flutter sobre cada estado de «Cancelar una agenda» (vista 23 C, #455), en
// 360x640 y 412x915, con texto 1,0 y 2,0. Va aparte del resto del QA: la guía de contraste lee los
// colores de la captura y con las fuentes reales da falsos negativos (con las cajas de Ahem lee el
// color de verdad).

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista23_455_arnes.dart';

void main() {
  sinFuentesReales455();

  for (final tamano in [chico455, grande455]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in Estado455.values) {
        group('${estado.rotulo} · ${sufijo455(tamano, escala)}', () {
          testWidgets('tamaño de toque Android (48 dp)', (tester) async {
            final h = tester.ensureSemantics();
            await llegarA455(tester, estado, tamano: tamano, escala: escala);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            h.dispose();
            await desmontar455(tester);
          });
          testWidgets('tamaño de toque iOS (44 pt)', (tester) async {
            final h = tester.ensureSemantics();
            await llegarA455(tester, estado, tamano: tamano, escala: escala);
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            h.dispose();
            await desmontar455(tester);
          });
          testWidgets('todo lo tocable tiene nombre', (tester) async {
            final h = tester.ensureSemantics();
            await llegarA455(tester, estado, tamano: tamano, escala: escala);
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            h.dispose();
            await desmontar455(tester);
          });
          testWidgets('contraste del texto', (tester) async {
            final h = tester.ensureSemantics();
            await llegarA455(tester, estado, tamano: tamano, escala: escala);
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            h.dispose();
            await desmontar455(tester);
          });
        });
      }
    }
  }
}
