// QA de las vistas 20 y 21 (HU-JOR-003, #146): las guías de accesibilidad de Flutter en cada estado, a
// 360×640 y 412×915, con el texto al 100 % y al 200 %. Sin las fuentes reales (con ellas el contraste da
// falsos negativos); el desborde de las filas se mide en `qa_vista20_21_acompaniamiento_146_test.dart`.
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_vista20_21_146_arnes.dart';

void main() {
  for (final entrada in estados146.entries) {
    for (final (nombreTam, tam) in [
      ('360x640', telefonoChico146),
      ('412x915', telefonoGrande146),
    ]) {
      for (final esc in [1.0, 2.0]) {
        testWidgets('${entrada.key} · $nombreTam · texto ×$esc · guías de accesibilidad', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          await entrada.value(tester, tam, esc);
          // Sin la fuente real el texto ancho puede desbordar: eso lo mide el otro archivo.
          tester.takeException();
          expect(esperado146[entrada.key]!(), findsWidgets, reason: 'no se llegó al estado');

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
