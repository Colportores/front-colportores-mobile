// QA de #508: contraste de texto (`textContrastGuideline`) en cada estado de la lista de la campaña.
// Va aparte, con la fuente de prueba: con las fuentes reales la guía lee el fondo de una captura con
// glifos de verdad y da falsos negativos (nota del carril, #335).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_agenda_campania_508_arnes.dart';

void main() {
  setUpAll(() => usarFuentesReales = false);
  tearDownAll(() => usarFuentesReales = true);

  for (final e in Estado508.values) {
    for (final tamano in tamanos) {
      for (final escala in escalas) {
        testWidgets(
          'contraste AA del texto: ${e.rotulo} · ${tamano.width.toInt()}x${tamano.height.toInt()} · ${escala}x',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await llegarA508(tester, e, escala: escala, tamano: tamano);

            await expectLater(tester, meetsGuideline(textContrastGuideline));
            if (e.conVerMas) {
              await irAlFinal(tester);
              await expectLater(tester, meetsGuideline(textContrastGuideline));
            }
            semantica.dispose();
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
