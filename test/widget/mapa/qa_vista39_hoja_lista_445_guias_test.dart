// QA r2 de la hoja de la casa desde la Lista (#445, PR #476): guías de accesibilidad de Flutter en el
// resumen y en la hoja arriba, con la fuente de prueba (el contraste con las reales da falsos negativos).
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_445_lista_arnes.dart';

void main() {
  for (final arriba in [false, true]) {
    for (final tamano in const [Size(360, 640), Size(412, 915)]) {
      for (final escala in const [1.0, 2.0]) {
        testWidgets(
          'guías · Lista ${arriba ? 'arriba' : 'resumen'} · ${tamano.width.toInt()}x${tamano.height.toInt()} x$escala',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await abrirHojaDeLaLista445(tester, arriba: arriba, tamano: tamano, escala: escala);

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
