// Guías de accesibilidad de Flutter sobre cada estado de «¿María no te pagó?» (decisión de Cristian,
// 03/11, #440): tamaño de toque (48 dp Android, 44 pt iOS) y nombre de todo lo tocable, en 360×640 y
// 412×915, con texto 1,0 y 2,0 y con la letra real. El contraste va en otro archivo, con la letra de
// prueba: la guía de contraste lee los colores de la captura y con las fuentes reales da falsos
// negativos.
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pregunta_al_cancelar_440_arnes.dart';

void main() {
  for (final tamano in [const Size(360, 640), const Size(412, 915)]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in EstadoPregunta440.values) {
        group('${estado.rotulo} · ${tamano.width.toInt()}x${tamano.height.toInt()} · x$escala', () {
          Future<void> verificar(WidgetTester tester, AccessibilityGuideline guia) async {
            final h = tester.ensureSemantics();
            final agenda = await llegarAPregunta440(tester, estado, tamano: tamano, escala: escala);
            await expectLater(tester, meetsGuideline(guia));
            await liberarPregunta440(tester, agenda);
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
        });
      }
    }
  }
}
