// Guías de accesibilidad de Flutter sobre los estados de la cita de ENTREGA que el QA de #536 no
// alcanzaba (23C·06, 23C·07 y 23B·02), en 360x640 y 412x915, con texto 1,0 y 2,0 (PR #678, #433).
// Va aparte: la guía de contraste lee los colores de la captura y con las fuentes reales da falsos
// negativos.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista23_entrega_433_arnes.dart';
import '../../helpers/qa_vista23_entrega_678_arnes.dart';

void main() {
  sinFuentesReales455();

  final guias = <String, AccessibilityGuideline>{
    'tamaño de toque Android (48 dp)': androidTapTargetGuideline,
    'tamaño de toque iOS (44 pt)': iOSTapTargetGuideline,
    'todo lo tocable tiene nombre': labeledTapTargetGuideline,
    'contraste del texto': textContrastGuideline,
  };

  for (final tamano in [chico455, grande455]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in Estado678.values) {
        group('${estado.rotulo} · ${sufijo455(tamano, escala)}', () {
          for (final MapEntry(key: nombre, value: guia) in guias.entries) {
            testWidgets(nombre, (tester) async {
              final h = tester.ensureSemantics();
              await llegarA678(tester, estado, tamano: tamano, escala: escala);
              await expectLater(tester, meetsGuideline(guia));
              h.dispose();
              await desmontar455(tester);
            });
          }
        });
      }
    }
  }
}
