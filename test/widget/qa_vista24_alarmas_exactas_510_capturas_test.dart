// Capturas de la QA de «Aviso exacto» (#510, PR #617): cada estado a 360x640 y 412x915, con texto 1,0 y
// 2,0, con las fuentes reales. Solo corren con `--dart-define=QA_CAPTURAS=true` y van a
// `.dart_tool/qa_capturas/` (gitignored, nunca al commit).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_hojas_teclado_324_arnes.dart' show cargarTipografias, conCapturas;
import '../helpers/qa_vista24_alarmas_510_arnes.dart';

Future<void> _foto(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & tester.view.physicalSize);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa617_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  setUpAll(cargarTipografias);

  for (final estado in Estado617.values) {
    for (final tam in tamanos) {
      for (final escala in escalas) {
        testWidgets('captura ${estado.id} ${tam.nombre} t${escala.toInt()}', (tester) async {
          await llevarAlEstado617(tester, estado, tamano: tam, escala: escala);
          await tester.pump(const Duration(milliseconds: 400));
          await _foto(tester, '${estado.id}_${tam.nombre}_t${escala.toInt()}');
          expect(tester.takeException(), isNull);
        }, skip: !conCapturas);
      }
    }
  }
}
