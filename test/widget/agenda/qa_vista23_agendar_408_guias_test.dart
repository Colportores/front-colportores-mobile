// Guías de accesibilidad de Flutter sobre cada estado de «Agendar una visita» (vista 23 A, #408), en
// 360x640 y 412x915, con texto 1,0 y 2,0. Va aparte del resto del QA: la guía de contraste lee los
// colores de la captura y con las fuentes reales da falsos negativos (con las cajas de Ahem lee el color
// de verdad).
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista23_408_arnes.dart';

String _sufijo(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()}_x$e';

void main() {
  usarFuentesReales408 = false;

  for (final tamano in [chico, grande]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in Estado408.values) {
        group('${estado.rotulo} · ${_sufijo(tamano, escala)}', () {
          testWidgets('tamaño de toque Android (48 dp)', (tester) async {
            final h = tester.ensureSemantics();
            await llegarA(tester, estado, tamano: tamano, escala: escala);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            h.dispose();
          });
          testWidgets('tamaño de toque iOS (44 pt)', (tester) async {
            final h = tester.ensureSemantics();
            await llegarA(tester, estado, tamano: tamano, escala: escala);
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            h.dispose();
          });
          testWidgets('todo lo tocable tiene nombre', (tester) async {
            final h = tester.ensureSemantics();
            await llegarA(tester, estado, tamano: tamano, escala: escala);
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            h.dispose();
          });
          testWidgets('contraste del texto', (tester) async {
            final h = tester.ensureSemantics();
            await llegarA(tester, estado, tamano: tamano, escala: escala);
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            h.dispose();
          });
        });
      }
    }
  }
}
