// QA #610: guías de accesibilidad de Flutter sobre lo que suma el PR (varios respaldos juntos, la hoja
// de «Empezar sin recuperar» y la fila «Recuperar mi respaldo» de Configuración), en 360x640 y 412x915,
// con texto 1,0 y 2,0. Aparte del resto del QA por el contraste (ver el de #175).
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_recuperacion_175_arnes.dart';
import '../../helpers/qa_recuperacion_610_arnes.dart';

void main() {
  sinFuentesReales175();

  final guias = <String, AccessibilityGuideline>{
    'tamaño de toque Android (48 dp)': androidTapTargetGuideline,
    'tamaño de toque iOS (44 pt)': iOSTapTargetGuideline,
    'todo lo tocable tiene nombre': labeledTapTargetGuideline,
    'contraste del texto': textContrastGuideline,
  };

  for (final tamano in [chico175, grande175]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in Estado610.values) {
        group('${estado.rotulo} · ${sufijo175(tamano, escala)}', () {
          for (final g in guias.entries) {
            testWidgets(g.key, (tester) async {
              final h = tester.ensureSemantics();
              final a = await llegarA610(tester, estado, tamano: tamano, escala: escala);
              expect(tester.takeException(), isNull);
              await expectLater(tester, meetsGuideline(g.value));
              await liberar175(tester, a);
              h.dispose();
            });
          }
        });
      }

      group('Configuración con la fila «Recuperar mi respaldo» · ${sufijo175(tamano, escala)}', () {
        for (final g in guias.entries) {
          testWidgets(g.key, (tester) async {
            final h = tester.ensureSemantics();
            final a = ArnesRecuperacion();
            await abrirAppHastaConfiguracion610(tester, a, tamano: tamano, escala: escala);
            expect(find.text('Recuperar mi respaldo'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await expectLater(tester, meetsGuideline(g.value));
            h.dispose();
          });
        }
      });
    }
  }
}
