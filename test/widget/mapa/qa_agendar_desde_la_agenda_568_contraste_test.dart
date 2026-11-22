// QA de #568, contraste del texto (`textContrastGuideline`) en cada estado del flujo. Con la letra de
// prueba (Ahem): con la real la guía da falsos negativos.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_agendar_desde_la_agenda_568_arnes.dart';
import 'qa_agendar_desde_la_agenda_568_guias_test.dart' show Estado568, llegarA;

void main() {
  setUpAll(() => usarFuentesReales = false);
  tearDownAll(() => usarFuentesReales = true);

  for (final estado in Estado568.values) {
    for (final tam in tamanos) {
      testWidgets('${estado.rotulo} · ${tam.width.toInt()}×${tam.height.toInt()}: contraste AA', (
        tester,
      ) async {
        await llegarA(tester, estado, tam, 1);

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
