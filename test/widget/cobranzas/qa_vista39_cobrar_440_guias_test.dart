// Guías de accesibilidad de Flutter sobre cada estado de «¿Qué venta?» (vista 39, C·08, #440), en
// 360x640 y 412x915, con texto 1,0 y 2,0. Va aparte del resto del QA: la guía de contraste lee los
// colores de la captura y con las fuentes reales da falsos negativos.

import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_440_arnes.dart';

void main() {
  sinFuentesReales440();

  for (final tamano in [chico440, grande440]) {
    for (final escala in [1.0, 2.0]) {
      for (final estado in Estado440.values) {
        // Con la fuente de prueba (Ahem, cada letra mide 1 em) el saldo de seis cifras a 2× no entra en
        // la fila y desborda: es del tipo de letra de la prueba. Con las fuentes reales no desborda
        // (matriz de `qa_vista39_cobrar_440_test.dart`), pero la columna de texto queda de ~70 dp.
        if (estado == Estado440.c08Muchas && escala == 2.0) continue;
        group('${estado.rotulo} · ${sufijo440(tamano, escala)}', () {
          Future<void> verificar(WidgetTester tester, AccessibilityGuideline guia) async {
            final h = tester.ensureSemantics();
            final m = await llegarA440(tester, estado, tamano: tamano, escala: escala);
            await expectLater(tester, meetsGuideline(guia));
            await liberar440(tester, m);
            h.dispose();
          }

          testWidgets(
            'tamaño de toque Android (48 dp)',
            (t) => verificar(t, androidTapTargetGuideline),
          );
          testWidgets('tamaño de toque iOS (44 pt)', (t) => verificar(t, iOSTapTargetGuideline));
          testWidgets(
            'todo lo tocable tiene nombre',
            (t) => verificar(t, labeledTapTargetGuideline),
          );
          testWidgets('contraste del texto', (t) => verificar(t, textContrastGuideline));
        });
      }
    }
  }
}
