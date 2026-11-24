// QA de #516 (PR #736, vista 24 grupo B con la sección AVISOS): contraste del texto
// (`textContrastGuideline`) en cada estado y tamaño. Va en su propio archivo con la letra de prueba: con
// las fuentes reales la guía da falsos negativos (lee los píxeles del trazo suavizado).
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_vista24_avisos_516_arnes.dart';

void main() {
  for (final tam in tamanos736) {
    for (final estado in Estado736.values) {
      testWidgets('${estado.id} · ${tam.nombre}: contraste del texto', (tester) async {
        final semantica = tester.ensureSemantics();
        await llevarAlEstado736(tester, estado, tamano: tam);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }
  }
}
