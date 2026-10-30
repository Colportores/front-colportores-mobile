// QA de #491: contraste AA del texto (`textContrastGuideline`) de la hoja con «Visitas agendadas».
// Con las fuentes reales la guía da falsos negativos: va con la fuente de prueba.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista23_491_arnes.dart';

void main() {
  setUpAll(() => usarFuentesReales = false);
  tearDownAll(() => usarFuentesReales = true);

  for (final e in Estado491.values) {
    for (final escala in escalas) {
      testWidgets('contraste AA del texto: ${e.rotulo} · 390 · ${escala}x', (tester) async {
        final semantica = tester.ensureSemantics();
        await montar491(tester, e, escala: escala, tamano: const Size(390, 3000), enElMapa: false);
        await tester.pump(const Duration(milliseconds: 400));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
