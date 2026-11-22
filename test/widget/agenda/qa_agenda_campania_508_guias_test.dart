// QA de #508: guías de accesibilidad de la pestaña «Agenda» en cada estado de la lista de la campaña
// (tamaño de toque Android e iOS, etiqueta en lo tocable) × 360x640 / 412x915 × 1,0 / 2,0.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_agenda_campania_508_arnes.dart';

void main() {
  for (final e in Estado508.values) {
    for (final tamano in tamanos) {
      for (final escala in escalas) {
        testWidgets(
          'guías de toque y etiqueta: ${e.rotulo} · ${tamano.width.toInt()}x${tamano.height.toInt()} · ${escala}x',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await llegarA508(tester, e, escala: escala, tamano: tamano);

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            if (e.conVerMas) {
              await irAlFinal(tester);
              await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
              await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
              await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            }
            semantica.dispose();
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
