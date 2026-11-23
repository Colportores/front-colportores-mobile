// Guías de accesibilidad de Flutter sobre los estados de la vista 30 B (#168) que las guías del
// implementador (`anular_cobro_424_guias_test.dart`) no recorren: «Otro» sin texto, la confirmación con
// tarjeta, anulando, cargando, el cobro que ya no está, el error de lectura y un cobro de ayer. Con las
// cajas de Ahem la guía de contraste lee el color de verdad.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_anular_cobro_168_arnes.dart';

const _estados = [
  Estado168.otroVacio,
  Estado168.confirmarTarjeta,
  Estado168.anulando,
  Estado168.cargando,
  Estado168.ausente,
  Estado168.errorDeLectura,
  Estado168.ayer,
];

void main() {
  usarFuentesReales408 = false;
  for (final tamano in const [chico168, grande168]) {
    for (final escala in const [1.0, 2.0]) {
      for (final estado in _estados) {
        group('${estado.rotulo} · ${sufijo168(tamano, escala)}', () {
          Future<void> verificar(WidgetTester tester, AccessibilityGuideline guia) async {
            final h = tester.ensureSemantics();
            final repo = await llegarA168(tester, estado, tamano, escala);
            await expectLater(tester, meetsGuideline(guia));
            expect(tester.takeException(), isNull);
            await liberar168(tester, repo);
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
