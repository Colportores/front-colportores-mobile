// Capturas PNG de cada estado nuevo de #748 con las fuentes reales, para mirarlas contra las piezas vecinas
// (37B·01 y 37B·03). Solo corre con `--dart-define=QA_CAPTURAS=true`; las deja en `.dart_tool/qa_capturas/`
// (no se commitea).
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_no_se_envio_748_estados.dart';
import '../../helpers/qa_vista37_387_arnes.dart';

void main() {
  for (final MapEntry(key: nombre, value: montar) in estados748.entries) {
    for (final tamano in [telefonoChico748, telefonoGrande748]) {
      for (final escala in [1.0, 2.0]) {
        final archivo =
            '${nombre.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_'
            '${tamano.width.toInt()}x${tamano.height.toInt()}_${escala.toInt()}x';
        testWidgets('captura: $archivo', (tester) async {
          await cargarFuentes37(tester);
          await montar(tester, tamano, escala);
          await tester.pump(const Duration(milliseconds: 600));
          await capturar37(tester, archivo);
        }, skip: !conCapturas37);
      }
    }
  }
}
