// Guías de accesibilidad del centro de notificaciones (#156, PR #481) en cada estado, a los dos
// tamaños de referencia y con texto 1.0 y 2.0: tamaño de toque (Android e iOS), etiqueta en todo lo
// tocable y contraste. Sin las fuentes reales (con ellas `textContrastGuideline` da falsos
// negativos). Ninguno queda saltado: todos corren.
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_centro_notificaciones_156_arnes.dart';

void main() {
  for (final tam in tamanos) {
    for (final escala in escalas) {
      for (final estado in EstadoCentro.values) {
        testWidgets(
          '${estado.rotulo} · ${tam.nombre} · texto ${escala}x · guías de accesibilidad',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await llevarAlEstado(tester, estado, tamano: tam, escala: escala);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          },
        );
      }
    }
  }
}
