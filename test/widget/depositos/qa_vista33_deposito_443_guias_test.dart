// QA de «Registrar depósito» (vista 33 D, #443): los 16 estados alcanzables × 360×640 y 412×915 ×
// texto 1,0 y 2,0, con las guías de toque (48 dp Android, 44 pt iOS) y de rótulo, sin overflow. Con
// `--dart-define=QA_CAPTURAS=true` guarda una captura de cada celda en `.dart_tool/qa_capturas/`.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista33_deposito_443_arnes.dart';

void main() {
  for (final estado in Estado443.values) {
    for (final tamano in tamanos443) {
      for (final escala in escalas443) {
        final nombre = '${estado.name}_${sufijo443(tamano, escala)}';
        testWidgets('guías de toque y sin overflow: $nombre', (tester) async {
          final semantica = tester.ensureSemantics();
          final arnes = await llegarA443(tester, estado, tamano: tamano, escala: escala);
          expect(tester.takeException(), isNull, reason: 'overflow en $nombre');

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await capturar443(tester, nombre);

          await soltar443(tester, arnes);
          expect(tester.takeException(), isNull);
          semantica.dispose();
        });
      }
    }
  }
}
