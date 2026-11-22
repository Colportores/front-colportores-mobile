// QA de «Dados de baja» (vista 11, HU-UBI-007, #473, PR #559): las guías de accesibilidad de Flutter
// (tamaño de toque de Android e iOS, etiqueta en lo tocable y contraste del texto) en cada estado nuevo,
// a 360×640 y 412×915, con el texto al 100 % y al 200 %. Archivo aparte con la letra de prueba (Ahem):
// con las fuentes reales el `textContrastGuideline` da falsos negativos.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista11_bajas_473_arnes.dart';

void main() {
  setUpAll(() => usarFuentesReales211 = false);

  for (final tamano in [telefonoChico211, telefonoGrande211]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in EstadoBajas.values) {
        final donde =
            '${estado.rotulo} a ${tamano.width.toInt()}×${tamano.height.toInt()} al '
            '${(escala * 100).toInt()} %';

        testWidgets('guías de toque, nombre y contraste en $donde', (tester) async {
          final h = tester.ensureSemantics();
          await llegarABajas(tester, estado, tamano: tamano, escala: escala);
          // El estado "reactivando" tiene el botón apagado a propósito (exento de contraste en WCAG).
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          if (estado != EstadoBajas.reactivando) {
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          }
          h.dispose();
        });
      }
    }
  }
}
