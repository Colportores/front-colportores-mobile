// QA de «Edificio y sus deptos» (vista 39, #452, PR #705): la guía de contraste de Flutter en cada estado.
// Con las fuentes reales da falsos negativos: acá se usa la letra de prueba y solo a 1,0×.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_452_arnes.dart';

void main() {
  setUpAll(() => usarFuentesReales452 = false);

  for (final estado in Estado452.values) {
    for (final (tamano, nombreTamano) in [(chico452, '360x640'), (grande452, '412x915')]) {
      testWidgets('contraste · ${estado.id} · $nombreTamano', (tester) async {
        final semantica = tester.ensureSemantics();
        await llegarA452(tester, estado, tamano: tamano);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }
  }
}
