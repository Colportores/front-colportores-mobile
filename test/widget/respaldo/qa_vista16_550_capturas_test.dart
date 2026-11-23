// Capturas PNG de #550 (vista 16, 16E y 16F), solo con `--dart-define=QA_CAPTURAS=true`, en
// `.dart_tool/qa_capturas/` (gitignored). Con las fuentes reales de `assets/fonts/`.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista16_550_arnes.dart';

void main() {
  for (final estado in Estado550.values) {
    for (final (nombre, ancho, alto, escala) in tamanos550) {
      testWidgets('captura ${estado.rotulo} $nombre', (tester) async {
        await armarEstado550(
          tester,
          estado,
          ancho: ancho,
          alto: alto,
          escala: escala,
          fuentesReales: true,
        );
        await capturar550(tester, '${estado.name}_$nombre');
        expect(tester.takeException(), isNull);
      }, skip: !conCapturas);
    }
  }
}
