// QA de #491: guías de accesibilidad de la hoja de la casa con «Visitas agendadas» en cada estado
// (tamaño de toque Android e iOS, etiqueta en lo tocable) × 360 / 412 de ancho × 1,0 / 2,0. La hoja va
// en una pantalla alta: un nodo cortado por el borde del scroll da falsos negativos en las guías.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista23_491_arnes.dart';

void main() {
  for (final e in Estado491.values) {
    for (final tamano in tamanos) {
      for (final escala in escalas) {
        testWidgets(
          'guías de toque y etiqueta: ${e.rotulo} · ${tamano.width.toInt()} · ${escala}x',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await montar491(
              tester,
              e,
              escala: escala,
              tamano: Size(tamano.width, 3000),
              enElMapa: false,
            );
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            semantica.dispose();
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
