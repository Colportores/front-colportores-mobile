// QA de #692 · vista 41, 41E·03, 03B y 03C: las guías de accesibilidad de Flutter (objetivo táctil de
// Android y de iOS, nombre en lo tocable y contraste) en los 9 estados del botón de ubicación, a
// 360x640 y 412x915 con el texto a 1,0 y a 2,0. Sin las fuentes reales: con ellas
// `textContrastGuideline` da falsos negativos.
import 'package:flutter_test/flutter_test.dart';

import 'qa_vista41e_692_arnes.dart';

void main() {
  for (final MapEntry(key: nombreTamano, value: tamano) in tamanos692.entries) {
    for (final escala in [1.0, 2.0]) {
      for (final MapEntry(key: nombre, value: armar) in escenas692.entries) {
        testWidgets('$nombre · $nombreTamano · texto $escala: guías de accesibilidad', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          await armar(tester, tamano, escala);

          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        });
      }
    }
  }

  testWidgets('el rótulo no entra en la semántica y la brújula y el botón sí, cada uno una vez', (
    tester,
  ) async {
    final semantica = tester.ensureSemantics();
    await escenas692['41E·03C girar con rumbo: cono y brújula, con el rótulo']!(
      tester,
      tamanos692['360x640']!,
      1,
    );

    expect(
      find.bySemanticsLabel('Seguir y girar con el teléfono'),
      findsNothing,
      reason: 'el rótulo lo oye el lector en el anuncio y en el nombre del botón',
    );
    expect(find.bySemanticsLabel('Ubicación: Seguir y girar con el teléfono'), findsOneWidget);
    expect(find.bySemanticsLabel('Brújula: volver al norte'), findsOneWidget);
    semantica.dispose();
  });
}
