// QA de «la cuota que toca» en la hoja de la casa (vista 39, C·01 y C·02, #591, PR #634): las guías de
// accesibilidad de Flutter (objetivo táctil de Android y de iOS, etiqueta de lo tocable y contraste del
// texto) en cada estado y tamaño. Va aparte de `qa_vista39_cuota_591_test.dart` porque el contraste se mide
// con la fuente de prueba: con las fuentes reales `textContrastGuideline` da falsos negativos.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_591_arnes.dart';

const _tamanos = [t360x640, t412x915];
const _escalas = [1.0, 2.0];

void main() {
  for (final arriba in [false, true]) {
    for (final estado in Estado591.values) {
      for (final tamano in _tamanos) {
        for (final escala in _escalas) {
          final vista = arriba ? 'C02' : 'C01';
          testWidgets('guías · $vista · ${estado.name} · ${sufijo445(tamano, escala)}', (
            tester,
          ) async {
            final semantica = tester.ensureSemantics();
            await llegarA591(tester, estado, tamano: tamano, escala: escala, arriba: arriba);
            await tester.pump(const Duration(milliseconds: 100));

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          });
        }
      }
    }
  }
}
