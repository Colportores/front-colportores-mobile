// QA del PR #377 (#335, vista 12): las guías de toque (Android e iOS) y de etiquetas de Flutter en cada
// estado del canvas (A01 a A08, A01b y las variantes de A04), con las fuentes reales. El contraste va
// aparte (`qa_vista12_cuenta_regresiva_335_contraste_test.dart`): su guía lee los colores de la captura
// y con las fuentes reales se confunde.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_vista12_335_arnes.dart';

Future<void> _guias(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
}

void main() {
  group('guías de toque y etiquetas en cada estado del canvas 12', () {
    for (final e in Estado12.values) {
      for (final (tam, escala) in [
        (const Size(390, 844), 1.0),
        (const Size(360, 640), 2.0),
        (const Size(320, 568), 2.0),
      ]) {
        testWidgets('${e.rotulo} a ${tam.width.toInt()}×${tam.height.toInt()} ×$escala: toque de '
            '48 dp y etiquetas', (tester) async {
          final semantica = tester.ensureSemantics();
          await llegarA(tester, e, tam: tam, escala: escala);

          await _guias(tester);
          semantica.dispose();
          await cerrarApp(tester);
        });
      }
    }
  });

  group('A03 · las guías en cada punto de la cuenta', () {
    for (final (tam, escala) in [(const Size(390, 844), 1.0), (const Size(360, 640), 2.0)]) {
      testWidgets('a ${tam.width.toInt()}×${tam.height.toInt()} ×$escala, a 0, 15, 30, 45 y 59 s', (
        tester,
      ) async {
        final semantica = tester.ensureSemantics();
        final esc = await llegarA(tester, Estado12.a03, tam: tam, escala: escala, segundos: 0);
        var pasados = 0;
        for (final s in [0, 15, 30, 45, 59]) {
          await esc.reloj.pasar(tester, s - pasados);
          pasados = s;
          await _guias(tester);
        }
        semantica.dispose();
        await cerrarApp(tester);
      });
    }
  });
}
