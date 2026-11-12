// Guías de accesibilidad de Flutter sobre cada estado del detalle y de «Modificar agenda» (vista 23 C,
// #409), en 360x640 y 412x915, con texto 1,0 y 2,0. Va aparte del resto del QA: la guía de contraste
// lee los colores de la captura y con las fuentes reales da falsos negativos (con las cajas de Ahem lee
// el color de verdad).
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista23_409_arnes.dart';

String _suf(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()}_x$e';

void main() {
  sinFuentesReales409();

  for (final tamano in [chico409, grande409]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in Estado409.values) {
        group('${estado.rotulo} · ${_suf(tamano, escala)}', () {
          testWidgets('tamaño de toque Android (48 dp)', (tester) async {
            final h = tester.ensureSemantics();
            await llegarA409(tester, estado, tamano: tamano, escala: escala);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            h.dispose();
          });
          testWidgets('tamaño de toque iOS (44 pt)', (tester) async {
            final h = tester.ensureSemantics();
            await llegarA409(tester, estado, tamano: tamano, escala: escala);
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            h.dispose();
          });
          testWidgets('todo lo tocable tiene nombre', (tester) async {
            final h = tester.ensureSemantics();
            await llegarA409(tester, estado, tamano: tamano, escala: escala);
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            h.dispose();
          });
          testWidgets('contraste del texto', (tester) async {
            final h = tester.ensureSemantics();
            await llegarA409(tester, estado, tamano: tamano, escala: escala);
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            h.dispose();
          });
        });
      }
    }
  }
}
