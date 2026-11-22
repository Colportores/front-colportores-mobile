// Capturas de la QA de #383 (PR #469): el aviso de la cuenta restringida con algo abierto y la
// pantalla de la cuenta a la que se llega. Solo corren con `--dart-define=QA_CAPTURAS=true` y van a
// `.dart_tool/qa_capturas/` (gitignored, nunca al commit). Letra real: aparte del archivo de las
// guías, porque con la real `textContrastGuideline` da falsos negativos.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_cuenta_restringida_383_arnes.dart';
import '../helpers/qa_hojas_teclado_324_arnes.dart' show cargarTipografias, conCapturas;

Future<void> _foto(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final tam = tester.view.physicalSize;
    final img = await capa.toImage(Offset.zero & tam);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa383_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

void main() {
  setUpAll(cargarTipografias);

  const tamanos = [Size(360, 640), Size(412, 915)];
  for (final tam in tamanos) {
    for (final escala in [1.0, 2.0]) {
      final sufijo = '${tam.width.toInt()}x${tam.height.toInt()}_t${escala.toInt()}';
      for (final estado in [EstadoCuenta.suspendida, EstadoCuenta.pendienteAsignacion]) {
        final e = estado == EstadoCuenta.suspendida ? 'susp' : 'pend';
        testWidgets('captura $e $sufijo', (tester) async {
          fijarTamano(tester, tam, texto: escala);
          var colgada = await enElInicio(tester, contestara: estado);
          await abrirElAlta(tester);
          await llegaLaRespuesta(tester, colgada);
          await tester.pump(const Duration(milliseconds: 500));
          await _foto(tester, 'alta_${e}_$sufijo');
          expect(aviso, findsOneWidget);

          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          await _foto(tester, 'cuenta_${e}_$sufijo');
          expect(titulo, findsOneWidget);

          // Configuración abierta (otra sesión, mismo estado).
          colgada = await enElInicio(tester, contestara: estado);
          await abrirConfiguracion(tester);
          await llegaLaRespuesta(tester, colgada);
          await tester.pump(const Duration(milliseconds: 500));
          await _foto(tester, 'config_${e}_$sufijo');
        }, skip: !conCapturas);
      }
    }
  }
}
