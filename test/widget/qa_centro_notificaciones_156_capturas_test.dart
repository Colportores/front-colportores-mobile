// Capturas del centro de notificaciones (#156, PR #481), con las fuentes reales: cada estado a
// 360x640 y 412x915, con texto 1.0 y 2.0. Solo corren con `--dart-define=QA_CAPTURAS=true` y van a
// `.dart_tool/qa_capturas/` (gitignored, nunca al commit).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_centro_notificaciones_156_arnes.dart';
import '../helpers/qa_hojas_teclado_324_arnes.dart' show cargarTipografias, conCapturas;

Future<void> _foto(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final tam = tester.view.physicalSize;
    final img = await capa.toImage(Offset.zero & tam);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa156_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  setUpAll(cargarTipografias);

  for (final tam in tamanos) {
    for (final escala in escalas) {
      for (final estado in EstadoCentro.values) {
        if (estado == EstadoCentro.muchos) continue;
        testWidgets('captura ${estado.id} ${tam.nombre} t${escala.toInt()}', (tester) async {
          await llevarAlEstado(tester, estado, tamano: tam, escala: escala);
          await tester.pump(const Duration(milliseconds: 300));
          await _foto(tester, '${estado.id}_${tam.nombre}_t${escala.toInt()}');
          expect(tester.takeException(), isNull);
        }, skip: !conCapturas);
      }
    }
  }
}
