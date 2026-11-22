// QA de #704 · vista 06, 06C·03: las guías de accesibilidad de Flutter (objetivo táctil de Android y
// de iOS, nombre en lo tocable y contraste) en cada estado de la hoja «Agendados», a 360x640 y
// 412x915 con el texto a 1,0 y a 2,0. Sin las fuentes reales: con ellas `textContrastGuideline` da
// falsos negativos.
import 'package:flutter_test/flutter_test.dart';

import 'qa_vista06_agendados_704_arnes.dart';

void main() {
  for (final MapEntry(key: nombreTamano, value: tamano) in tamanos704.entries) {
    for (final escala in [1.0, 2.0]) {
      for (final MapEntry(key: nombre, value: armar) in escenas704.entries) {
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
