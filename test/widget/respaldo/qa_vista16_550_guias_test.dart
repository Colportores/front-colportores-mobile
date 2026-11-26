// QA de #550, vista 16 (16E y 16F): las guías de accesibilidad de Flutter y el desborde en cada estado
// del canvas, a 360×640 y 412×915 con la letra al 100 % y al 200 %. El contraste se mide solo con la
// letra normal (con la fuente de prueba, a 2× no alcanza el enlace del aviso).
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista16_550_arnes.dart';

void main() {
  for (final estado in Estado550.values) {
    group(estado.rotulo, () {
      for (final (nombre, ancho, alto, escala) in tamanos550) {
        testWidgets('$nombre: sin desborde y con las guías de toque y de etiqueta', (tester) async {
          final handle = tester.ensureSemantics();
          await armarEstado550(tester, estado, ancho: ancho, alto: alto, escala: escala);

          expect(tester.takeException(), isNull, reason: 'overflow o error de render');
          if (estado.esHoja) {
            await tester.ensureVisible(
              estado == Estado550.hoja02 ? botonConfirmarSeguir : botonVolver,
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
          }
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          if (escala == 1) await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    });
  }

  testWidgets('16F·03 a 360×640 con letra al 200 %: «Ocultar hasta mañana» se toca y oculta', (
    tester,
  ) async {
    final mundo = await armarEstado550(tester, Estado550.hoy03, ancho: 360, alto: 640, escala: 2);

    await tester.ensureVisible(botonOcultar);
    await tester.pump();
    await tester.tap(botonOcultar);
    await tester.pumpAndSettle();

    expect(franjaRevocada, findsNothing);
    expect(marcaEngranaje, findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(mundo.container.read(franjaDriveOcultaProvider).value, isNotNull);
  });
}
