// QA de la hoja de la casa arriba (vista 39, C·02, #445, PR #476): las guías de accesibilidad de Flutter
// (objetivo táctil de Android y de iOS, etiqueta de lo tocable y contraste del texto) en cada estado y
// tamaño. Va aparte de `qa_vista39_hoja_arriba_445_test.dart` porque el contraste se mide con la fuente
// de prueba: con las fuentes reales `textContrastGuideline` da falsos negativos.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_445_arnes.dart';

const _tamanos = [t360x640, t412x915];
const _escalas = [1.0, 2.0];

void main() {
  for (final estado in Estado445.values) {
    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        testWidgets('guías · ${estado.name} · ${sufijo445(tamano, escala)}', (tester) async {
          final semantica = tester.ensureSemantics();
          await llegarA445(tester, estado, tamano: tamano, escala: escala);
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
