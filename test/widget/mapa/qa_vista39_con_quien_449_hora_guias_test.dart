// QA r3 de la vista 39 (#449, PR #463): las guías de accesibilidad con la hora de alta en la segunda
// línea. Aparte y SIN fuentes reales (con las reales `textContrastGuideline` da falsos negativos).
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_449_arnes.dart';
import '../../helpers/qa_vista39_449_hora_arnes.dart';

void main() {
  for (final tamano in [t360x640, t412x915]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in EstadoHora449.values) {
        testWidgets(
          '${estado.name} · ${sufijo449(tamano, escala)}: toque Android/iOS, nombre en lo tocable y '
          'contraste',
          (tester) async {
            final handle = tester.ensureSemantics();
            await llegarAHora449(tester, estado, tamano: tamano, escala: escala);
            await tester.pump(const Duration(milliseconds: 300));

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            handle.dispose();
          },
        );
      }
    }
  }
}
