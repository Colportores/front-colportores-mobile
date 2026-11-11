// QA de la entrega para otro día y «Entregas pendientes» (#435, vista 27 grupo C): cada estado de las
// tres pantallas a 360×640 y 412×915 con texto 1,0 y 2,0, sin overflow ni texto cortado, con captura
// (`--dart-define=QA_CAPTURAS=true`). Las guías de accesibilidad van en `..._guias_test.dart`.
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista27_entrega_435_arnes.dart';

const _tamanos = [chico435, grande435];
const _escalas = [1.0, 2.0];

void main() {
  group('Sin overflow ni texto cortado, y con captura', () {
    for (final estado in Estado435.values) {
      for (final tamano in _tamanos) {
        for (final escala in _escalas) {
          testWidgets(
            '${estado.rotulo} · ${tamano.width.toInt()}×${tamano.height.toInt()} · ${escala}x',
            (tester) async {
              final m = await montar435(tester, estado, tamano: tamano, escala: escala);
              expect(tester.takeException(), isNull);
              sinTextoCortado435(tester);
              await capturar435(tester, nombreDeCaptura435(estado, tamano, escala));
              await soltar435(tester, m);
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });
}
