// QA de accesibilidad de «Devolución» (vista 31, HU-VEN-004, #161, PR #589): las cuatro guías de Flutter
// (tamaño de toque de Android e iOS, etiquetas y contraste) en cada estado, 360×640 y 412×915, texto
// 1,0 y 2,0. Va aparte de `qa_vista31_devolucion_161_test.dart` porque la guía de contraste da falsos
// negativos con las fuentes reales (se usa la fuente de prueba).
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista31_devolucion_161_arnes.dart';

void main() {
  setUpAll(() => usarFuentesReales161 = false);
  tearDownAll(() => usarFuentesReales161 = true);

  const tamanos = {'360x640': chico161, '412x915': grande161};

  group('Guías de accesibilidad por estado', () {
    for (final estado in Estado161.values) {
      for (final t in tamanos.entries) {
        for (final escala in const [1.0, 2.0]) {
          testWidgets('${estado.titulo} · ${t.key} · ×$escala', (tester) async {
            final semantica = tester.ensureSemantics();
            await llegar161(tester, estado, tamano: t.value, escala: escala);
            // Con la fuente de prueba (más ancha que Inter) algo puede desbordar a 2,0: el overflow
            // se mide con las fuentes reales en `qa_vista31_devolucion_161_test.dart`.
            tester.takeException();
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          });
        }
      }
    }
  });
}
