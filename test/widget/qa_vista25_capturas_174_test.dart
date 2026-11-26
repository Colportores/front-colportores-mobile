// Capturas PNG de la vista 25 (Sincronización y respaldo, #174, PR #489) para la revisión visual del
// QA: cada estado en los dos tamaños del proyecto con el texto al 100 % y al 200 %, con las fuentes
// reales. Solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`
// (gitignored: nunca se commitean). Sin la marca, el archivo no hace nada.
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_vista25_174_arnes.dart';

void main() {
  if (!conCapturas25) return;

  for (final estado in Estado25.values) {
    for (final tam in tamanos25) {
      for (final escala in escalas25) {
        testWidgets('captura ${nombre25(estado, tam, escala)}', (tester) async {
          await cargarFuentes25(tester);
          await llegar25(tester, estado, tamano: tam, escala: escala);
          await tester.pump(const Duration(milliseconds: 400));
          await capturar25(
            tester,
            '${estado.name}_${tam.width.toInt()}x${tam.height.toInt()}_x$escala',
          );
        });
      }
    }
  }
}
