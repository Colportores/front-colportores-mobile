// QA de «Transferencia de materiales» (vista 40, #512): contraste de texto (`textContrastGuideline`) en cada
// estado. Va en un archivo aparte porque con las fuentes reales la guía de Flutter da falsos negativos: acá
// se usa la fuente de prueba (no se cargan las reales).
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista40_512_arnes.dart';

void main() {
  for (final estado in estados512) {
    for (final tamano in [chico512, grande512]) {
      testWidgets('contraste · ${estado.id} ${estado.rotulo} · ${rotuloDeTamano512(tamano)}', (
        tester,
      ) async {
        final semantica = tester.ensureSemantics();
        await estado.armar(tester, tamano, 1);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }
  }
}
