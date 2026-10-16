// QA ronda 1 del PR #317 (issue #305, HU-UBI-001): contraste 4,5:1 de la hoja del alta en cada
// artboard (03A · 01 a 04) con «Registrar» fijo. Va aparte de `alta_ubicacion_qa_registrar_fijo_test.dart`
// porque `textContrastGuideline` da falsos negativos con las fuentes reales (el texto antialiasado
// mezcla el color con el fondo): acá se usa la fuente de prueba (Ahem) y solo se mira el color.
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_317_arnes.dart';

void main() {
  for (final estado in EstadoAlta.values) {
    for (final (tamano, escala) in [
      (telefonoChico, 1.0),
      (telefonoChico, 2.0),
      (telefonoGrande, 1.0),
    ]) {
      testWidgets(
        '${estado.rotulo} a ${tamano.width.toInt()}×${tamano.height.toInt()}, texto ${escala}x: '
        'contraste de texto 4,5:1 con «Registrar» deshabilitado y habilitado',
        (tester) async {
          final handle = tester.ensureSemantics();
          await abrirEn(tester, estado, tamano: tamano, escala: escala);
          expect(registrarHabilitado(tester), isFalse);
          await expectLater(tester, meetsGuideline(textContrastGuideline));

          await tocar(tester, find.text('Casa'));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          expect(find.byType(HojaAlta), findsOneWidget);
          handle.dispose();
        },
      );
    }
  }
}
