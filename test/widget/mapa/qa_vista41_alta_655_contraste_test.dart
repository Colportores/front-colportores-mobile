// QA de #655 (vista 41, entrega 1): el contraste (WCAG AA, 4,5:1) de los 11 artboards a 360x640 y
// 412x915 con texto 1,0. Aparte de las guías de toque: con las fuentes reales `textContrastGuideline`
// da falsos negativos (lee el fondo de una captura con glifos reales), así que acá van sin ellas.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista41_655_arnes.dart';

void main() {
  setUpAll(() => usarFuentesReales655 = false);

  for (final a in Artboard655.values) {
    for (final tamano in tamanos655) {
      final nombre = '${a.rotulo} · ${tamano.width.toInt()}x${tamano.height.toInt()}';
      testWidgets('contraste: $nombre', (tester) async {
        final semantica = tester.ensureSemantics();
        await llegarA655(tester, a, tamano: tamano);
        await tester.pump(const Duration(milliseconds: 500));

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }
  }
}
