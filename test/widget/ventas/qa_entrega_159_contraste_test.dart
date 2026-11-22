// QA de «Entregar ahora» (#159): la guía de contraste de texto en cada estado, a 360×640 y 412×915.
// Va en un archivo aparte y con la fuente de prueba: con las fuentes reales da falsos negativos
// (`usarFuentesReales408 = false`).
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_entrega_159_arnes.dart';

const _tamanos = [chico159, grande159];

void main() {
  group('Contraste', () {
    setUpAll(() => usarFuentesReales408 = false);
    tearDownAll(() => usarFuentesReales408 = true);
    for (final estado in Estado159.values) {
      for (final tamano in _tamanos) {
        testWidgets('${estado.rotulo} · ${tamano.width.toInt()}×${tamano.height.toInt()}', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          final m = await montar159(tester, estado, tamano: tamano);
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await soltar159(tester, m);
          handle.dispose();
        });
      }
    }
  });
}
