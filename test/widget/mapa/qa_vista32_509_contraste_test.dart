// Contraste de #509 (vista 32, PR #604): `textContrastGuideline` en «Ver borradas» (con «Se borra el …»)
// y en la hoja de baja con entrega pendiente. Va aparte: con las fuentes reales la guía de Flutter da
// falsos negativos (trazos de 1 px); con las cajas de Ahem lee el color de verdad.
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_vista32_509_arnes.dart';

void main() {
  setUpAll(() => usarFuentesReales = false);

  for (final estado in [
    EstadoBorradas.e05Una,
    EstadoBorradas.e05Tres,
    EstadoBorradas.e05SoloLectura,
    EstadoBorradas.e05FallaRestaurar,
  ]) {
    for (final escala in [1.0]) {
      // El color no depende de la escala; a 2,0× con cajas de Ahem la lista no deja ver el enlace.
      testWidgets('contraste · ${estado.rotulo} · ×$escala', (tester) async {
        final semantica = tester.ensureSemantics();
        await borradasEn(tester, estado, escala: escala);
        await verEnPantalla(tester, find.byKey(ClavesNotas.seBorraEl).first);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }
  }

  for (final estado in EstadoBaja509.values) {
    testWidgets('contraste · ${estado.rotulo}', (tester) async {
      final semantica = tester.ensureSemantics();
      await hojaEn(tester, estado);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });
  }
}
