// Capturas PNG de cada estado de la vista 37 (#387) con las fuentes reales, para mirarlas contra el canvas.
// Solo corre con `--dart-define=QA_CAPTURAS=true`; las deja en `.dart_tool/qa_capturas/` (no se commitea).
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista37_387_arnes.dart';
import '../../helpers/qa_vista37_387_estados.dart';

void main() {
  for (final MapEntry(key: nombre, value: montar) in estados37.entries) {
    for (final tamano in [telefonoChico37, telefonoGrande37]) {
      for (final escala in [1.0, 2.0]) {
        final archivo =
            '${nombre.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_'
            '${tamano.width.toInt()}x${tamano.height.toInt()}_${escala.toInt()}x';
        testWidgets('captura: $archivo', (tester) async {
          await cargarFuentes37(tester);
          await montar(tester, tamano, escala);
          // Las animaciones del botón y de las rutas terminan antes de medir el contraste.
          await tester.pump(const Duration(milliseconds: 600));
          await capturar37(tester, archivo);
        }, skip: !conCapturas37);
      }
    }
  }
}
