// Contraste del texto de «¿María no te pagó?» (decisión de Cristian, 03/11, #440) en cada estado, con la
// guía de Flutter. Va aparte de las demás guías: lee los colores de la captura y con las fuentes reales
// da falsos negativos, así que usa la letra de prueba (a 1,0 solo: a 2,0 una palabra como «equivoqué»
// mide 1 em por letra y desborda por la letra, no por la hoja).
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pregunta_al_cancelar_440_arnes.dart';
import '../../helpers/qa_vista23_408_arnes.dart' show usarFuentesReales408;

void main() {
  usarFuentesReales408 = false;

  for (final estado in EstadoPregunta440.values) {
    testWidgets('contraste del texto · ${estado.rotulo}', (tester) async {
      final h = tester.ensureSemantics();
      final agenda = await llegarAPregunta440(
        tester,
        estado,
        tamano: const Size(412, 915),
        escala: 1,
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await liberarPregunta440(tester, agenda);
      h.dispose();
    });
  }
}
