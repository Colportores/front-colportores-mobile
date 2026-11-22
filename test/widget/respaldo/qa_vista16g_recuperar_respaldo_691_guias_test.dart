// Guías de accesibilidad de la vista 16, artboards 16G (#691), en cada estado y tamaño: tamaño de
// toque de Android y de iOS, etiquetas y contraste. Va aparte del archivo de la matriz porque con las
// fuentes reales `textContrastGuideline` da falsos negativos: acá corre con la fuente de prueba.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista16g_691_arnes.dart';
import '../../helpers/recuperacion_arnes.dart';

void main() {
  late ArnesRecuperacion arnes;

  setUp(() => arnes = ArnesRecuperacion());

  for (final estado in Estado16G.values) {
    for (final (nombre, ancho, alto, escala) in tamanos) {
      testWidgets('${estado.rotulo} · $nombre', (tester) async {
        final semantica = tester.ensureSemantics();
        await abrirApp(
          tester,
          arnes,
          ancho: ancho,
          alto: alto,
          escala: escala,
          fuentesReales: false,
        );
        await armarEstado(tester, arnes, estado);
        // Los botones de las animaciones de entrada (200 ms) y el aviso ya asentados.
        await tester.pump(const Duration(milliseconds: 400));

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }
  }
}
