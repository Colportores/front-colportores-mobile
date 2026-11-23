// QA de «Foto del ticket de tarjeta» (#427, PR #601): contraste de cada estado (`textContrastGuideline`).
// Va en un archivo aparte y con la letra de prueba: con las fuentes reales el suavizado de la guía da
// falsos negativos en letra chica (ver el carril de QA).
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista29c_427_arnes.dart';

void main() {
  for (final estado in Estado427.values) {
    for (final tam in tamanos) {
      for (final escala in escalas) {
        testWidgets(
          'contraste · ${estado.artboard} ${estado.rotulo} · ${tam.nombre} · texto ${escala.toStringAsFixed(1)}',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await llevarAlEstado427(tester, estado, tamano: tam, escala: escala);
            await tester.pump(const Duration(milliseconds: 400));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          },
        );
      }
    }
  }

  for (final tam in tamanos) {
    testWidgets('contraste · 29A-03 registrada con foto · ${tam.nombre}', (tester) async {
      final semantica = tester.ensureSemantics();
      await llevarA29A03(tester, tamano: tam);
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });
  }
}
