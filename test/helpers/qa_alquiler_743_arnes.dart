// Ayudas del QA de «Mi alquiler» (HU-CTA-007, vista 38C, #389): fuentes reales para ver y medir el
// texto, capturas PNG (solo con `--dart-define=QA_CAPTURAS=true`, fuera del repo) y las comprobaciones
// de «nada cortado» y «ninguna palabra partida».
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const conCapturas743 = bool.fromEnvironment('QA_CAPTURAS');

/// Los hallazgos de QA que siguen sin arreglar corren solo con `--dart-define=QA_HALLAZGOS=true`.
const conHallazgos743 = bool.fromEnvironment('QA_HALLAZGOS');

bool _fuentesCargadas = false;

/// Carga las fuentes de `assets/fonts/`: sin ellas `flutter_test` pinta cajas de ancho fijo.
Future<void> cargarFuentes743(WidgetTester tester) async {
  if (_fuentesCargadas) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    final raiz = Platform.environment['FLUTTER_ROOT'];
    final iconos = File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (raiz != null && iconos.existsSync()) {
      final bytes = iconos.readAsBytesSync();
      final cargador = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
  });
  _fuentesCargadas = true;
}

/// La pantalla entera como PNG, solo con `QA_CAPTURAS`.
Future<void> capturar743(WidgetTester tester, String nombre) async {
  if (!conCapturas743) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/743_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado743(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// Ninguna palabra se parte en dos renglones: cada palabra, sola, cabe en el ancho que tiene su texto.
/// Devuelve las palabras partidas.
List<String> palabrasPartidas743(WidgetTester tester) {
  final partidas = <String>[];
  for (final e in find.byType(RichText).evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    final span = p.text;
    final plano = span.toPlainText();
    if (plano.trim().isEmpty) continue;
    final estilo = (span is TextSpan ? span.style : null) ?? const TextStyle();
    for (final palabra in plano.split(RegExp(r'\s+')).where((w) => w.length > 3)) {
      final medida = TextPainter(
        text: TextSpan(text: palabra, style: estilo),
        textDirection: TextDirection.ltr,
        textScaler: p.textScaler,
      )..layout();
      if (medida.width > p.size.width + 0.5) partidas.add('$palabra (${plano.length} car.)');
    }
  }
  return partidas;
}
