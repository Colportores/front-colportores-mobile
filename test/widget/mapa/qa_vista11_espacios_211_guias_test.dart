// QA de la vista 11 «Espacios» (HU-UBI-007, #211, PR #468): las guías de accesibilidad de Flutter
// (tamaño de toque de Android e iOS, etiqueta en lo tocable y contraste del texto) en cada estado y a
// 360×640 y 412×915. Archivo aparte con la letra de prueba (Ahem): con las fuentes reales el
// `textContrastGuideline` da falsos negativos.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista11_211_arnes.dart';

void main() {
  setUpAll(() => usarFuentesReales211 = false);

  for (final tamano in [telefonoChico211, telefonoGrande211]) {
    for (final estado in EstadoV11.values) {
      final donde = '${estado.rotulo} a ${tamano.width.toInt()}×${tamano.height.toInt()}';

      testWidgets('tamaño de toque de Android (48 dp) en $donde', (tester) async {
        final h = tester.ensureSemantics();
        await llegarA(tester, estado, tamano: tamano);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        h.dispose();
      });

      testWidgets('tamaño de toque de iOS (44 dp) en $donde', (tester) async {
        final h = tester.ensureSemantics();
        await llegarA(tester, estado, tamano: tamano);
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        h.dispose();
      });

      testWidgets('toda acción tocable tiene nombre en $donde', (tester) async {
        final h = tester.ensureSemantics();
        await llegarA(tester, estado, tamano: tamano);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        h.dispose();
      });

      testWidgets('contraste del texto (AA) en $donde', (tester) async {
        final h = tester.ensureSemantics();
        await llegarA(tester, estado, tamano: tamano);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        h.dispose();
      });

      testWidgets('tamaño de toque con el texto al 200 % en $donde', (tester) async {
        final h = tester.ensureSemantics();
        await llegarA(tester, estado, tamano: tamano, escala: 2);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        h.dispose();
      });
    }
  }
}
