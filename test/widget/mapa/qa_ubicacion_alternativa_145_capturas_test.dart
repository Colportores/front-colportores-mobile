// QA de #145 (HU-UBI-013, vista 22 grupo A): capturas de cada estado de la sección «COBRANZA», del
// selector y de la hoja de quitar, con las fuentes reales, a 360×640 y 412×915 con texto 1,0 y 2,0.
// No corren solas: `--dart-define=QA_CAPTURAS=true` las deja en `.dart_tool/qa_capturas/145_*.png`
// (fuera de git). La app no tiene tema oscuro: el tema claro es el único.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_ubicacion_alternativa_145_arnes.dart';

const _sacarCapturas = bool.fromEnvironment('QA_CAPTURAS');

Future<void> _cargarFuentes() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await cargador.load();
  }
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & tester.view.physicalSize, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/145_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

String _archivo(String s) => s
    .replaceAll(RegExp(r'[·…:«»]'), '')
    .replaceAll(RegExp(r'\s+'), '_')
    .replaceAll('×', 'x')
    .toLowerCase();

void main() {
  setUpAll(() async {
    if (_sacarCapturas) await _cargarFuentes();
  });

  group('capturas', skip: !_sacarCapturas, () {
    for (final MapEntry(key: nombre, value: preparar) in estados145.entries) {
      for (final tamano in tamanos145) {
        for (final escala in escalas145) {
          final cuando = '${tamano.width.toInt()}x${tamano.height.toInt()}_x$escala';
          testWidgets('$nombre · $cuando', (tester) async {
            await preparar(tester, tamano, escala);
            await tester.pump(const Duration(milliseconds: 600));
            expect(tester.takeException(), isNull);
            await _capturar(tester, '${_archivo(nombre)}_$cuando');
          });
        }
      }
    }
  });
}
