// QA de #715 (casas «fuera del área» en el mapa, #713): las guías de accesibilidad de Flutter (objetivo
// táctil de Android y de iOS, nombre en lo tocable y contraste) en cada estado nuevo, a 360x640 y
// 412x915 con el texto a 1,0 y a 2,0. Sin las fuentes reales: con ellas `textContrastGuideline` da
// falsos negativos.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_mapa_fuera_del_area_715_arnes.dart';

void main() {
  for (final MapEntry(key: nombreTamano, value: tamano) in tamanos715.entries) {
    for (final escala in [1.0, 2.0]) {
      for (final MapEntry(key: nombre, value: armar) in escenas715.entries) {
        testWidgets('$nombre · $nombreTamano · texto $escala: guías de accesibilidad', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          await armar(tester, tamano, escala);

          expect(tester.takeException(), isNull);
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
