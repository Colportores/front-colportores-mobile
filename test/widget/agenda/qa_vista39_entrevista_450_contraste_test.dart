// Contraste de texto de la vista 39 (#450) con la guía de Flutter. Va en un archivo aparte: la guía
// lee los colores de la captura y con las fuentes reales (trazos de 1 px, suavizados) da falsos
// negativos, así que acá se usan las cajas de Ahem, que dan el color de verdad.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_450_arnes.dart';

void main() {
  setUpAll(() => usarFuentesReales = false);
  tearDownAll(() => usarFuentesReales = true);

  for (final estado in Estado39.values) {
    for (final escala in escalas39) {
      testWidgets('${estado.rotulo} · x${escala.toStringAsFixed(0)}: contraste de texto AA', (
        tester,
      ) async {
        final semantica = tester.ensureSemantics();
        await llegar(tester, estado, escala: escala);

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }
  }
}
