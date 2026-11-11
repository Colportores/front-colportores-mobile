// QA de «Cuenta Drive» (#184): contraste de texto (`textContrastGuideline`) en cada estado. Va en un
// archivo aparte porque con las fuentes reales la guía de Flutter da falsos negativos: acá se usa la
// fuente de prueba (`usarFuentesReales408 = false`).
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_drive_184_arnes.dart';

void main() {
  setUpAll(() => usarFuentesReales408 = false);
  tearDownAll(() => usarFuentesReales408 = true);

  for (final e in Estado184.values) {
    for (final t in [chico184, grande184]) {
      testWidgets('contraste · ${e.rotulo} · ${t.width.toInt()}x${t.height.toInt()}', (
        tester,
      ) async {
        final semantica = tester.ensureSemantics();
        await montar184(tester, e, tamano: t);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }
  }
}
