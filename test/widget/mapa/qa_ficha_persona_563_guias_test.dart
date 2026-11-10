// QA de la ficha de una persona (vista 32B, HU-UBI-009, #141, PR #563): las guías de accesibilidad de
// Flutter (tamaño de toque de Android e iOS, etiqueta en lo tocable y contraste del texto) en cada
// estado, a 360×640 y 412×915, con el texto al 100 % y al 200 %. Archivo aparte con la letra de prueba
// (Ahem): con las fuentes reales el `textContrastGuideline` da falsos negativos.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_ficha_persona_563_arnes.dart';

void main() {
  setUpAll(() => usarFuentesReales563 = false);

  for (final tamano in [telefonoChico563, telefonoGrande563]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in EstadoFicha.values) {
        final donde =
            '${estado.rotulo} a ${tamano.width.toInt()}×${tamano.height.toInt()} al '
            '${(escala * 100).toInt()} %';

        testWidgets('guías de toque y nombre en $donde', (tester) async {
          final h = tester.ensureSemantics();
          await llegarAFicha(tester, estado, tamano: tamano, escala: escala);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          h.dispose();
        });

        testWidgets('contraste del texto en $donde', (tester) async {
          final h = tester.ensureSemantics();
          await llegarAFicha(tester, estado, tamano: tamano, escala: escala);
          // El botón apagado mientras reactiva está exento de contraste (WCAG 1.4.3).
          if (estado == EstadoFicha.reactivandoPersona || estado == EstadoFicha.reactivandoDepto) {
            h.dispose();
            return;
          }
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          h.dispose();
        });

        testWidgets('guías al final de la lista en $donde', (tester) async {
          final h = tester.ensureSemantics();
          await llegarAFicha(tester, estado, tamano: tamano, escala: escala);
          final listas = find.byType(ListView);
          if (listas.evaluate().isEmpty) {
            h.dispose();
            return;
          }
          final lista = tester.state<ScrollableState>(
            find.descendant(of: listas.first, matching: find.byType(Scrollable)).first,
          );
          lista.position.jumpTo(lista.position.maxScrollExtent);
          await tester.pump(const Duration(milliseconds: 400));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          if (estado != EstadoFicha.reactivandoPersona && estado != EstadoFicha.reactivandoDepto) {
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          }
          h.dispose();
        });
      }
    }
  }
}
