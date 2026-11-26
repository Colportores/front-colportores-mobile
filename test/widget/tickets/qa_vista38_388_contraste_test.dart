// QA de «Mis tickets» y del detalle (vista 38B, #388): contraste (`textContrastGuideline`) de cada
// estado en los dos teléfonos. Va aparte y sin fuentes reales: con ellas la guía da falsos negativos.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista38_388_arnes.dart';

void main() {
  usarFuentesReales443 = false;

  for (final estado in Estado388.values) {
    for (final tamano in tamanos388) {
      final nombre = '${estado.name}_${sufijo388(tamano, 1)}';
      testWidgets('contraste: $nombre', (tester) async {
        final semantica = tester.ensureSemantics();
        final armado = await llegarA388(tester, estado, tamano: tamano);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await soltar388(tester, armado);
        semantica.dispose();
      });
    }
  }
}
