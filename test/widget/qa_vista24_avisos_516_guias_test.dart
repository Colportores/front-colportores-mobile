// QA de #516 (PR #736, vista 24 grupo B con la sección AVISOS): las guías de accesibilidad de Flutter
// (tamaño de toque en Android e iOS y controles con etiqueta) en cada estado, tamaño y escala de texto.
// El contraste va en `qa_vista24_avisos_516_contraste_test.dart` (con la letra de prueba). Acá, con las
// fuentes reales: con la de prueba (cada letra un cuadrado) el selector de hora del sistema desborda a 2,0x
// y no es de la app.
import 'package:flutter_test/flutter_test.dart';

import '../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../helpers/qa_vista24_avisos_516_arnes.dart';

void main() {
  setUpAll(cargarFuentesReales);

  for (final tam in [...tamanos736, tamanoChico736]) {
    for (final escala in escalas736) {
      for (final estado in Estado736.values) {
        testWidgets('${estado.id} · ${tam.nombre} · texto ${escala}x: guías de toque y etiquetas', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          await llevarAlEstado736(tester, estado, tamano: tam, escala: escala);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          semantica.dispose();
        });
      }
    }
  }
}
