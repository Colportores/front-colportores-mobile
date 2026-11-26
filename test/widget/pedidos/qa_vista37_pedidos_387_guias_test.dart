// QA de la vista 37 (#387): guías de accesibilidad (tamaño de toque de Android y de iOS, etiquetas y
// contraste) y overflow de cada estado de los 14 artboards y de los estados que el canvas no dibuja, a
// 360×640 y 412×915 con el texto al 100 % y al 200 %. Con Ahem: el contraste con las fuentes reales lo mide
// mal (ver nota del carril); los colores son los mismos.

import 'package:colportores_mobile/features/pedidos/presentation/textos_pedidos.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista37_387_arnes.dart';
import '../../helpers/qa_vista37_387_estados.dart';

void main() {
  for (final MapEntry(key: nombre, value: montar) in estados37.entries) {
    for (final tamano in [telefonoChico37, telefonoGrande37]) {
      for (final escala in [1.0, 2.0]) {
        final etiqueta = '$nombre · ${tamano.width.toInt()}×${tamano.height.toInt()} · $escala×';
        testWidgets('guías y overflow: $etiqueta', (tester) async {
          final manejador = tester.ensureSemantics();
          await montar(tester, tamano, escala);
          // Las animaciones del botón y de las rutas terminan antes de medir el contraste.
          await tester.pump(const Duration(milliseconds: 600));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          manejador.dispose();
        });
      }
    }
  }

  test('los estados del canvas están todos en la matriz', () {
    for (final id in [
      '37A·01', '37A·08', '37A·02', '37A·03', '37A·04', '37A·05', '37A·06', '37A·07', //
      '37B·01', '37B·02', '37B·03', '37B·04', '37B·05', '37B·06',
    ]) {
      expect(estados37.keys.any((k) => k.startsWith(id)), isTrue, reason: id);
    }
    expect(TextosPedidos.tituloArmar, isNotEmpty);
  });
}
