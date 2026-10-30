// QA del aviso de privacidad del alta de persona (#445, PR #476): guías de accesibilidad de Flutter en
// cada estado del aviso, con la fuente de prueba (el contraste con las reales da falsos negativos).
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_445_aviso_arnes.dart';

void main() {
  for (final estado in EstadoAviso445.values) {
    for (final tamano in const [Size(360, 640), Size(412, 915)]) {
      for (final escala in const [1.0, 2.0]) {
        testWidgets(
          'guías · aviso ${estado.name} · ${tamano.width.toInt()}x${tamano.height.toInt()} x$escala',
          (tester) async {
            final semantica = tester.ensureSemantics();
            await llegarAlAviso445(tester, estado, tamano: tamano, escala: escala);

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
