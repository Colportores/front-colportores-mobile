// QA de #145 (HU-UBI-013, vista 22 grupo A): las guías de accesibilidad y el desborde en cada estado de
// la sección «COBRANZA» de la ficha, del selector «¿Dónde le cobrás?» y de la hoja «¿Quitar …?», a
// 360×640 y 412×915 con texto 1,0 y 2,0.
//
// Lo que el implementador no midió: `androidTapTargetGuideline`, `iOSTapTargetGuideline`,
// `labeledTapTargetGuideline` y `textContrastGuideline` (sus tests miran solo el alto de la tarjeta y de
// «Quitar» a 390 px) ni los dos tamaños chicos con la ficha entera. Un `RenderFlex overflowed` hace
// fallar el test. Ojo: con la fuente de prueba (Ahem) `textContrastGuideline` no ve el texto atenuado
// de la tarjeta «dada de baja»: eso se mide aparte, en `qa_ubicacion_alternativa_145_contraste_test.dart`.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_ubicacion_alternativa_145_arnes.dart';

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  for (final MapEntry(key: nombre, value: preparar) in estados145.entries) {
    for (final tamano in tamanos145) {
      for (final escala in escalas145) {
        final cuando = '${tamano.width.toInt()}×${tamano.height.toInt()} · texto $escala';
        testWidgets('$nombre · $cuando: sin desborde y con las cuatro guías', (tester) async {
          final semantica = tester.ensureSemantics();
          await preparar(tester, tamano, escala);
          // Las animaciones de entrada (hoja, snack) terminan antes de medir.
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull);
          await _guias(tester);
          semantica.dispose();
        });
      }
    }
  }
}
