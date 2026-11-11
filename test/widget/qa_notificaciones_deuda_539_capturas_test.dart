// Capturas de QA de #539 / PR #623, con las fuentes reales: el aviso sobre la lista del centro y la
// campana con «99+». Solo corren con `--dart-define=QA_CAPTURAS=true` y van a
// `.dart_tool/qa_capturas/` (gitignored, nunca al commit).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/historial_notificaciones_falsos.dart';
import '../helpers/qa_centro_notificaciones_156_arnes.dart';
import '../helpers/qa_hojas_teclado_324_arnes.dart' show cargarTipografias, conCapturas;

Future<void> _foto(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & tester.view.physicalSize);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa539_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  setUpAll(cargarTipografias);

  for (final tam in tamanos) {
    for (final escala in escalas) {
      testWidgets('captura aviso sobre la lista ${tam.nombre} t${escala.toInt()}', (tester) async {
        final arnes = CentroArnes(avisos: cincoDelCanvas())..destinos.todosExisten = false;
        await abrirCentro(tester, arnes, tamano: Size(tam.ancho, tam.alto), texto: escala);
        await tester.drag(centroLista, const Offset(0, -4000));
        await tester.pumpAndSettle();
        await tester.tap(filaDe('e'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await _foto(tester, 'aviso_${tam.nombre}_t${escala.toInt()}');
        expect(tester.takeException(), isNull);
      }, skip: !conCapturas);
    }
  }
}
