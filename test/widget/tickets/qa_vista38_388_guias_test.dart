// QA de «Mis tickets» y del detalle (vista 38B, #388): los 23 estados alcanzables × 360×640 y 412×915 ×
// texto 1,0 y 2,0, con las guías de toque (48 dp Android, 44 pt iOS) y de rótulo, sin overflow. Con
// `--dart-define=QA_CAPTURAS=true` guarda una captura de cada celda en `.dart_tool/qa_capturas/`.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista38_388_arnes.dart';

void main() {
  for (final estado in Estado388.values) {
    for (final tamano in tamanos388) {
      for (final escala in escalas388) {
        final nombre = '${estado.name}_${sufijo388(tamano, escala)}';
        testWidgets('guías de toque y sin overflow: $nombre', (tester) async {
          final semantica = tester.ensureSemantics();
          final armado = await llegarA388(tester, estado, tamano: tamano, escala: escala);
          expect(tester.takeException(), isNull, reason: 'overflow en $nombre');

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await capturar388(tester, nombre);

          await soltar388(tester, armado);
          expect(tester.takeException(), isNull);
          semantica.dispose();
        });
      }
    }
  }
}
