// QA de accesibilidad de la baja de persona y «Ver bajas» (HU-UBI-011, #143, PR #485): las cuatro guías
// de Flutter (objetivo táctil de Android y de iOS, etiqueta en cada objetivo, contraste del texto) en cada
// estado de la hoja y de «Mostrar bajas», a 360×640 y 412×915, y con el texto en 2,0 a 360×640.
//
// Va aparte del resto con `usarFuentesReales = false`: la guía de contraste lee el color del texto de la
// captura, y con las fuentes reales (trazos de 1 px, suavizados) da falsos negativos; con las cajas de
// Ahem lee el color de verdad.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_vista32d_baja_143_arnes.dart';

const _casos = [(Size(360, 640), 1.0), (Size(412, 915), 1.0), (Size(360, 640), 2.0)];

Future<void> _guias(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  handle.dispose();
}

void main() {
  usarFuentesReales = false;

  group('hoja de baja · guías de accesibilidad', () {
    for (final estado in EstadoHoja.values) {
      for (final (tam, escala) in _casos) {
        testWidgets('${estado.rotulo} a ${tam.width.toInt()}x${tam.height.toInt()} texto $escala', (
          tester,
        ) async {
          await hojaEn(tester, estado, tamano: tam, escala: escala);
          await _guias(tester);
        });
      }
    }
  });

  group('Mostrar bajas · guías de accesibilidad', () {
    for (final estado in EstadoBajas.values) {
      for (final (tam, escala) in _casos) {
        testWidgets('${estado.rotulo} a ${tam.width.toInt()}x${tam.height.toInt()} texto $escala', (
          tester,
        ) async {
          await bajasEn(tester, estado, tamano: tam, escala: escala);
          await _guias(tester);
        });
      }
    }
  });
}
