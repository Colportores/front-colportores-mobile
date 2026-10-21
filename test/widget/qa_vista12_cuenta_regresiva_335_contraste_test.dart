// QA del PR #377 (#335, vista 12): la guía de contraste de texto de Flutter (WCAG AA, 4,5:1) en cada
// estado del canvas y en cada punto de la cuenta regresiva, donde el rótulo cruza el borde del
// relleno. Sin las fuentes del proyecto a propósito: la guía lee los colores de la captura y con
// trazos de 1 px suavizados (Inter 13,5) da un contraste falso; con las cajas de Ahem lee el color de
// verdad. El contraste con las fuentes reales de los botones apagados lo miden, por píxeles, los
// tests de `qa_vista12_cuenta_regresiva_335_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_vista12_335_arnes.dart';

void main() {
  setUpAll(() => usarFuentesReales = false);
  tearDownAll(() => usarFuentesReales = true);

  group('contraste de texto en cada estado del canvas 12', () {
    for (final e in Estado12.values) {
      for (final tam in const [Size(390, 844), Size(360, 640)]) {
        testWidgets('${e.rotulo} a ${tam.width.toInt()}×${tam.height.toInt()}: el texto se lee a '
            '4,5:1', (tester) async {
          final semantica = tester.ensureSemantics();
          await llegarA(tester, e, tam: tam);

          tester.takeException();
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
          await cerrarApp(tester);
        });
      }
    }
  });

  group('A03 · el contraste en cada punto de la cuenta (el texto cruza el borde del relleno)', () {
    testWidgets('a 0, 6, 15, 30, 45 y 59 s', (tester) async {
      final semantica = tester.ensureSemantics();
      final esc = await llegarA(tester, Estado12.a03, segundos: 0);
      var pasados = 0;
      for (final s in [0, 6, 15, 30, 45, 59]) {
        await esc.reloj.pasar(tester, s - pasados);
        pasados = s;
        tester.takeException();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }
      semantica.dispose();
      await cerrarApp(tester);
    });
  });
}
