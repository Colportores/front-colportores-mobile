// QA de la ficha del depto con «Registrar visita» (vista 11·04, HU-VIS-005, #151, PR #574): las guías de
// accesibilidad de Flutter (tamaño de toque de Android e iOS, etiqueta en lo tocable y contraste del
// texto) en cada estado y tamaño. Archivo aparte con la letra de prueba (Ahem): con las fuentes reales
// el `textContrastGuideline` da falsos negativos.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_depto_151_arnes.dart';

void main() {
  usarFuentesReales151 = false;

  for (final tamano in const [telefonoChico151, telefonoGrande151]) {
    for (final escala in const [1.0, 2.0]) {
      for (final e in Estado151.values) {
        final donde = '${e.rotulo} a ${tamano.width.toInt()}×${tamano.height.toInt()} a $escala×';

        testWidgets('tamaño de toque de Android (48 dp) en $donde', (tester) async {
          final h = tester.ensureSemantics();
          await llegar151(tester, e, tamano: tamano, escala: escala);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          h.dispose();
        });

        testWidgets('tamaño de toque de iOS (44 dp) en $donde', (tester) async {
          final h = tester.ensureSemantics();
          await llegar151(tester, e, tamano: tamano, escala: escala);
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          h.dispose();
        });

        testWidgets('toda acción tocable tiene nombre en $donde', (tester) async {
          final h = tester.ensureSemantics();
          await llegar151(tester, e, tamano: tamano, escala: escala);
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          h.dispose();
        });

        testWidgets('contraste del texto (AA) en $donde', (tester) async {
          final h = tester.ensureSemantics();
          await llegar151(tester, e, tamano: tamano, escala: escala);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          h.dispose();
        });
      }
    }
  }
}
