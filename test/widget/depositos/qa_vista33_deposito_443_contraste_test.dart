// QA de «Registrar depósito» (vista 33 D, #443): contraste (`textContrastGuideline`) de cada estado en
// los dos teléfonos. Va aparte y sin fuentes reales: con ellas la guía da falsos negativos.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista33_deposito_443_arnes.dart';

void main() {
  usarFuentesReales443 = false;

  for (final estado in Estado443.values) {
    for (final tamano in tamanos443) {
      final nombre = '${estado.name}_${sufijo443(tamano, 1)}';
      testWidgets('contraste: $nombre', (tester) async {
        final semantica = tester.ensureSemantics();
        final arnes = await llegarA443(tester, estado, tamano: tamano);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await soltar443(tester, arnes);
        semantica.dispose();
      });
    }
  }
}
