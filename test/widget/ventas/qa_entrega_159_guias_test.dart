// QA de «Entregar ahora» (#159): las guías de accesibilidad de Flutter en cada estado, a 360×640 y
// 412×915 con texto 1,0 y 2,0. El contraste va en otro archivo (`..._contraste_test.dart`).
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_entrega_159_arnes.dart';

const _tamanos = [chico159, grande159];
const _escalas = [1.0, 2.0];

void main() {
  group('Toque y etiquetas', () {
    for (final estado in Estado159.values) {
      for (final tamano in _tamanos) {
        for (final escala in _escalas) {
          testWidgets(
            '${estado.rotulo} · ${tamano.width.toInt()}×${tamano.height.toInt()} · ${escala}x',
            (tester) async {
              final handle = tester.ensureSemantics();
              final m = await montar159(tester, estado, tamano: tamano, escala: escala);
              await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
              await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
              await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
              await soltar159(tester, m);
              handle.dispose();
            },
          );
        }
      }
    }
  });
}
