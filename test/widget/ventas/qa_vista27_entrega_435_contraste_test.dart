// QA de la entrega para otro día y «Entregas pendientes» (#435): la guía de contraste de Flutter en cada
// estado. Va aparte y con la fuente de prueba: con las fuentes reales da falsos negativos.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista27_entrega_435_arnes.dart';

void main() {
  setUpAll(() => usarFuentesReales408 = false);
  tearDownAll(() => usarFuentesReales408 = true);

  group('Contraste del texto', () {
    for (final estado in Estado435.values) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('${estado.rotulo} · ${escala}x', (tester) async {
          final handle = tester.ensureSemantics();
          final m = await montar435(tester, estado, escala: escala);
          // Con la fuente de prueba cada letra mide un em: un desborde acá es de la fuente, no de la
          // pantalla (los desbordes se miran con las fuentes reales en `qa_vista27_entrega_435_test`).
          tester.takeException();
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          await soltar435(tester, m);
          handle.dispose();
        });
      }
    }
  });
}
