// QA de «Vender» con varias personas entrevistadas y de «Ir a la entrevista» (vista 39, C·06 / C·07 / R·05;
// #661, PR #668): las guías de accesibilidad de Flutter en cada estado, tamaño y escala de texto. Van aparte
// y SIN fuentes reales: con las reales `textContrastGuideline` da falsos negativos.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_661_arnes.dart';

void main() {
  usarFuentesReales = false;

  for (final tamano in [t360x640, t412x915]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in Estado661.values) {
        testWidgets(
          '${estado.name} · ${sufijo661(tamano, escala)}: toque Android/iOS, nombre en lo tocable y '
          'contraste',
          (tester) async {
            final handle = tester.ensureSemantics();
            await llegarA661(tester, estado, tamano: tamano, escala: escala);
            await tester.pump(const Duration(milliseconds: 400));

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
