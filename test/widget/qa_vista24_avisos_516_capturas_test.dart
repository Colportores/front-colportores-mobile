// Capturas de la QA de #516 (PR #736): cada estado de la sección AVISOS a 360x640 y 412x915, con texto 1,0
// y 2,0 y las fuentes reales. Solo corren con `--dart-define=QA_CAPTURAS=true` y van a
// `.dart_tool/qa_capturas/` (gitignored, nunca al commit).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show Scrollable;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_hojas_teclado_324_arnes.dart' show cargarTipografias, conCapturas;
import '../helpers/qa_vista24_avisos_516_arnes.dart';

Future<void> _foto(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & tester.view.physicalSize);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa736_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  setUpAll(cargarTipografias);

  for (final estado in Estado736.values) {
    for (final tam in tamanos736) {
      for (final escala in escalas736) {
        testWidgets('captura ${estado.id} ${tam.nombre} t${escala.toInt()}', (tester) async {
          await llevarAlEstado736(tester, estado, tamano: tam, escala: escala);
          await tester.pump(const Duration(milliseconds: 400));
          await _foto(tester, '${estado.id}_${tam.nombre}_t${escala.toInt()}_a');
          // Lo de abajo: se desplaza al final.
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
          await tester.pump(const Duration(milliseconds: 400));
          await _foto(tester, '${estado.id}_${tam.nombre}_t${escala.toInt()}_b');
          expect(tester.takeException(), isNull);
        }, skip: !conCapturas);
      }
    }
  }
}
