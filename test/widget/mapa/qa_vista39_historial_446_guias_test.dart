// QA del Historial de la hoja de la casa (vista 39, C·03 y C·04, #446, PR #677): las guías de
// accesibilidad de Flutter (objetivo táctil de Android y de iOS, etiqueta de lo tocable y contraste del
// texto) en cada estado y tamaño. Va aparte de los demás tests de QA porque el contraste se mide con la
// fuente de prueba: con las fuentes reales `textContrastGuideline` da falsos negativos.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_446_arnes.dart';

void main() {
  for (final tamano in const [t360x640, t412x915]) {
    for (final escala in const [1.0, 2.0]) {
      for (final estado in Estado446.values) {
        testWidgets(
          'dado ${estado.name} a ${tamano.width.toInt()}×${tamano.height.toInt()} con letra ×$escala, '
          'cumple las guías de toque y de etiqueta',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await llegarA446(tester, estado, tamano: tamano, escala: escala);

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            semantica.dispose();
          },
        );
      }
    }
  }

  for (final tamano in const [t360x640, t412x915]) {
    for (final estado in Estado446.values) {
      testWidgets(
        'dado ${estado.name} a ${tamano.width.toInt()}×${tamano.height.toInt()}, el texto cumple el contraste',
        (tester) async {
          final semantica = tester.ensureSemantics();
          await llegarA446(tester, estado, tamano: tamano);
          // Los botones y los chips se animan unos 200 ms al tomar su color.
          await tester.pump(const Duration(milliseconds: 400));

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        },
      );
    }
  }
}
