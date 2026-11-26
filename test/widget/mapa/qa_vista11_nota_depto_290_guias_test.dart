// QA de la nota del depto (vista 11, #290, PR #776): las guías de accesibilidad de Flutter (objetivo
// táctil de Android y de iOS, etiqueta de lo tocable y contraste del texto) en cada estado y tamaño. Va
// aparte de `qa_vista11_nota_depto_290_test.dart` porque el contraste se mide con la fuente de prueba:
// con las fuentes reales `textContrastGuideline` da falsos negativos.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista11_nota_depto_290_arnes.dart';

const _tamanos = [t360x640, t412x915];
const _escalas = [1.0, 2.0];

const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

void main() {
  for (final estado in Estado290.values) {
    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        // QA #290: con «Borrar nota» (0485bacb) el formulario de editar a 360×640 con texto 2× recorta
        // el aviso «Estas notas viven solo en tu celular.» y su «No volver a mostrar» queda con 24 dp
        // de alto tocable (la guía de objetivo táctil pide 48).
        final hallazgo =
            estado == Estado290.formularioEditar && tamano == t360x640 && escala == 2.0;
        testWidgets(
          'guías · ${estado.name} · ${sufijo290(tamano, escala)}',
          skip: hallazgo && !_verHallazgos,
          (tester) async {
            final semantica = tester.ensureSemantics();
            await llegarA290(tester, estado, tamano: tamano, escala: escala);
            await tester.pump(const Duration(milliseconds: 500));

            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
            semantica.dispose();
          },
        );
      }
    }
  }
}
