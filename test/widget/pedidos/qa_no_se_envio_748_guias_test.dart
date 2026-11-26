// QA de #748 («No se envió»): guías de accesibilidad (tamaño de toque de Android y de iOS, etiquetas y
// contraste) y overflow de cada estado nuevo, a 360×640 y 412×915 con el texto al 100 % y al 200 %. Con Ahem:
// el contraste con las fuentes reales lo mide mal (ver nota del carril); los colores son los mismos.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_no_se_envio_748_estados.dart';

void main() {
  for (final MapEntry(key: nombre, value: montar) in estados748.entries) {
    for (final tamano in [telefonoChico748, telefonoGrande748]) {
      for (final escala in [1.0, 2.0]) {
        final etiqueta = '$nombre · ${tamano.width.toInt()}×${tamano.height.toInt()} · $escala×';
        testWidgets('guías y overflow: $etiqueta', (tester) async {
          final manejador = tester.ensureSemantics();
          await montar(tester, tamano, escala);
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          manejador.dispose();
        });
      }
    }
  }
}
