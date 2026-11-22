// QA de «Entrevista dada» y «Vender» (vista 39, R·04 → R·08; #648, PR #657): las guías de accesibilidad de
// Flutter en cada estado, tamaño y escala de texto. Van aparte y SIN fuentes reales: con las reales
// `textContrastGuideline` da falsos negativos.
//
// Los hallazgos van con `skip` (`--dart-define=QA_HALLAZGOS=true` los corre).
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_648_arnes.dart';

void main() {
  usarFuentesReales = false;

  for (final tamano in [t360x640, t412x915]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in Estado648.values) {
        testWidgets(
          '${estado.name} · ${sufijo648(tamano, escala)}: toque Android/iOS, nombre en lo tocable y '
          'contraste',
          (tester) async {
            final handle = tester.ensureSemantics();
            await llegarA648(tester, estado, tamano: tamano, escala: escala);
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
