// QA del PR #478 (#153, vista 24 grupo A): la guía de contraste de texto de Flutter en cada estado.
// Va en un archivo aparte: la guía lee los colores de la captura y con las fuentes reales (trazos de
// 1 px, suavizados) da falsos negativos; con las cajas de Ahem lee el color de verdad.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_vista24_153_arnes.dart';

void main() {
  setUpAll(() => usarFuentesReales = false);
  tearDownAll(() => usarFuentesReales = true);

  group('contraste de texto (AA) en cada estado del grupo A', () {
    for (final e in Estado24.values) {
      if (e == Estado24.a02) continue; // el botón apagado es un control deshabilitado (WCAG 1.4.3)
      testWidgets('${e.rotulo}: textContrastGuideline', (tester) async {
        final semantica = tester.ensureSemantics();
        await llegarA(tester, e, tam: const Size(412, 915));

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
        await cerrar(tester);
      });
    }
  });
}
