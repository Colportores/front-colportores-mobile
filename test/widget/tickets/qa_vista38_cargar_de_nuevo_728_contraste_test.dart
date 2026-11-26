// Contraste de texto de «Cargar de nuevo» de un cobro con tarjeta (#728, vista 38B·02 → 29 C). Va en un
// archivo aparte porque con las fuentes reales `textContrastGuideline` da falsos negativos (lee el fondo
// de una captura con glifos reales): acá se usa la fuente de prueba.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista38_388_arnes.dart';
import '../../helpers/qa_vista38_728_arnes.dart';

void main() {
  usarFuentesReales443 = false;
  for (final estado in Estado728.values) {
    for (final tamano in tamanos388) {
      for (final escala in escalas388) {
        final nombre = '${estado.name}_${sufijo388(tamano, escala)}';
        testWidgets('contraste de texto: $nombre', (tester) async {
          final semantica = tester.ensureSemantics();
          await llegarA728(tester, estado, tamano: tamano, escala: escala);
          // El overflow se mide con las fuentes reales (el otro archivo): la de prueba es más ancha.
          tester.takeException();

          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        });
      }
    }
  }
}
