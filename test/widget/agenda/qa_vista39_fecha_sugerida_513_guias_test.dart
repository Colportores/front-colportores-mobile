// Guías de accesibilidad de Flutter sobre cada estado de R·02/R·03 en «Agendar visita» (#513), en
// 360x640 y 412x915, con texto 1,0 y 2,0. Va aparte del resto del QA: la guía de contraste lee los
// colores de la captura y con las fuentes reales da falsos negativos (con las cajas de Ahem lee el color
// de verdad).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_513_arnes.dart';

/// Un nodo cortado por el borde del scroll da falso negativo en las guías de toque: se sube al inicio
/// (si no hay una hoja encima). El tamaño real de lo tocable nuevo se mide en el otro archivo.
Future<void> _alInicio(WidgetTester tester) async {
  final scroll = find.byType(SingleChildScrollView);
  if (scroll.evaluate().isEmpty || find.byType(BottomSheet).evaluate().isNotEmpty) return;
  final c = tester
      .state<ScrollableState>(
        find.descendant(of: scroll.first, matching: find.byType(Scrollable)).first,
      )
      .position;
  c.jumpTo(0);
  await tester.pump();
}

String _sufijo(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()}_x$e';

void main() {
  usarFuentesReales408 = false;

  for (final tamano in [chico, grande]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in Estado513.values) {
        group('${estado.rotulo} · ${_sufijo(tamano, escala)}', () {
          testWidgets('tamaño de toque Android (48 dp)', (tester) async {
            final h = tester.ensureSemantics();
            await llegarA513(tester, estado, tamano: tamano, escala: escala);
            await _alInicio(tester);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            h.dispose();
          });
          testWidgets('tamaño de toque iOS (44 pt)', (tester) async {
            final h = tester.ensureSemantics();
            await llegarA513(tester, estado, tamano: tamano, escala: escala);
            await _alInicio(tester);
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            h.dispose();
          });
          testWidgets('todo lo tocable tiene nombre', (tester) async {
            final h = tester.ensureSemantics();
            await llegarA513(tester, estado, tamano: tamano, escala: escala);
            await _alInicio(tester);
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            h.dispose();
          });
          testWidgets('contraste del texto', (tester) async {
            final h = tester.ensureSemantics();
            await llegarA513(tester, estado, tamano: tamano, escala: escala);
            await _alInicio(tester);
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            h.dispose();
          });
        });
      }
    }
  }
}
