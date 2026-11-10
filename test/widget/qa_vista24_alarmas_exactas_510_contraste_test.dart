// QA de «Aviso exacto» (#510, PR #617): contraste del aviso, de «Abrir ajustes» y del texto «No pudimos
// abrir los ajustes». Va en un archivo aparte y con la letra de prueba: con las fuentes reales el
// suavizado de `textContrastGuideline` da falsos negativos en letra chica (ver el carril de QA).
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_vista24_alarmas_510_arnes.dart';

void main() {
  const estados = [
    Estado617.avisoSolo,
    Estado617.avisoNoAbren,
    Estado617.avisoAbriendo,
    Estado617.avisoNotifBloqueadas,
    Estado617.avisoNotifSinPedir,
    Estado617.avisoErrorGuardar,
    Estado617.sinAvisoPermitidas,
  ];
  for (final estado in estados) {
    for (final tam in tamanos) {
      for (final escala in escalas) {
        testWidgets(
          'contraste · ${estado.rotulo} · ${tam.nombre} · texto ${escala.toStringAsFixed(1)}',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await llevarAlEstado617(tester, estado, tamano: tam, escala: escala);
            await tester.pump(const Duration(milliseconds: 400));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          },
        );
      }
    }
  }
}
