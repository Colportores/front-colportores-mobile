// QA r2 de la hoja de la casa desde la Lista (vista 05, #445, PR #476, commit 1d0e011): el modal abre en
// el resumen y sube a la hoja arriba con el asa. Matriz 360×640 / 412×915 × texto 1,0 / 2,0, con fuentes
// reales y capturas (`--dart-define=QA_CAPTURAS=true`).
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_vista39_445_arnes.dart';
import '../../helpers/qa_vista39_445_lista_arnes.dart';

void main() {
  for (final arriba in [false, true]) {
    for (final tamano in const [Size(360, 640), Size(412, 915)]) {
      for (final escala in const [1.0, 2.0]) {
        final nombre = '${arriba ? 'arriba' : 'resumen'} · ${sufijo445(tamano, escala)}';
        testWidgets('Lista: hoja $nombre', (tester) async {
          await cargarFuentes205(tester);
          await abrirHojaDeLaLista445(tester, arriba: arriba, tamano: tamano, escala: escala);

          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byKey(ClavesHojaCasa.asaDeLaLista)).height,
            greaterThanOrEqualTo(48),
          );
          final pestanas = find.byKey(ClavesHojaCasa.pestanas);
          expect(pestanas, arriba ? findsOneWidget : findsNothing);

          // Lo importante de cada altura se alcanza desplazando la hoja.
          final meta = arriba
              ? find.byKey(ClavesHojaCasa.agregarPersona)
              : find.byKey(ClavesHojaCasa.registrarVisita);
          await tester.ensureVisible(meta);
          await tester.pump();
          expect(meta, findsOneWidget);
          expect(tester.getRect(meta).bottom, lessThanOrEqualTo(tamano.height));
          expect(tester.takeException(), isNull);
          await capturar445(
            tester,
            'lista_${arriba ? 'arriba' : 'resumen'}_${sufijo445(tamano, escala)}',
          );
        });
      }
    }
  }

  testWidgets('Lista: tocar el asa dos veces seguidas deja la hoja en el resumen y no se cierra', (
    tester,
  ) async {
    await cargarFuentes205(tester);
    await abrirHojaDeLaLista445(tester, arriba: true);
    await tester.tap(find.byKey(ClavesHojaCasa.asaDeLaLista));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(ClavesHojaCasa.pestanas), findsNothing);
    expect(find.byKey(ClavesHojaCasa.asaDeLaLista), findsOneWidget);
  });
}
