// Guías de accesibilidad de #509 (vista 32, PR #604): tamaño de toque (Android e iOS) y etiquetas en cada
// estado de «Ver borradas» (32E·04/05) y de la hoja de baja con entrega pendiente (32D·02/03), a
// 360×640 y 412×915, con el texto a 1,0 y a 2,0. El contraste va en `_contraste_test.dart`.
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_vista32_509_arnes.dart';

void main() {
  for (final estado in EstadoBorradas.values) {
    for (final tamano in tamanos) {
      for (final escala in escalas) {
        testWidgets(
          'guías · ${estado.rotulo} · ${tamano.width.toInt()}x${tamano.height.toInt()} · ×$escala',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await borradasEn(tester, estado, tamano: tamano, escala: escala);
            // Un nodo cortado por el borde del scroll da falsos negativos: la primera tarjeta, a la vista.
            if (estado != EstadoBorradas.e04 && estado != EstadoBorradas.e05Vacia) {
              await verEnPantalla(tester, find.byKey(ClavesNotas.seBorraEl).first);
            }
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            semantica.dispose();
          },
        );
      }
    }
  }

  for (final estado in EstadoBaja509.values) {
    for (final tamano in tamanos) {
      for (final escala in escalas) {
        testWidgets(
          'guías · ${estado.rotulo} · ${tamano.width.toInt()}x${tamano.height.toInt()} · ×$escala',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await hojaEn(tester, estado, tamano: tamano, escala: escala);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            semantica.dispose();
          },
        );
      }
    }
  }
}
