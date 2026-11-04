// QA de las notas de una persona (HU-UBI-012, vista 32E, #144): las guías de accesibilidad de Flutter
// (tamaño de toque en Android y iOS, etiqueta en lo tocable y contraste del texto) en cada estado de la
// vista, en las cuatro celdas de la matriz (360x640 y 412x915, texto 1,0 y 2,0).
//
// Va aparte del archivo de capturas: `textContrastGuideline` con las fuentes reales da falsos
// negativos (el cuadro de la letra no coincide con el de la prueba), así que acá no se cargan.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista32e_144_arnes.dart';

void main() {
  for (final entrada in estados144.entries) {
    for (final celda in celdas144) {
      group('${entrada.key} · $celda', () {
        testWidgets('dado el estado, cuando lo miro, cumple las guías de accesibilidad', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          await entrada.value(tester, celda);

          expect(tester.takeException(), isNull, reason: 'sin overflow ni errores de layout');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        });
      });
    }
  }
}
