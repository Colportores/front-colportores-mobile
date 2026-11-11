// Arnés de QA de #432 (vender de punta a punta): fuentes reales, matriz de tamaños y capturas.
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`
// (gitignored). Los hallazgos con `skip` corren con `--dart-define=QA_HALLAZGOS=true`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const conCapturas = bool.fromEnvironment('QA_CAPTURAS');

/// Los hallazgos de la QA, con `skip`: `--dart-define=QA_HALLAZGOS=true` los corre para verlos fallar.
const verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

/// Las fuentes reales: `false` en el archivo de contraste (con ellas `textContrastGuideline` da
/// falsos negativos: lee el fondo de una captura con glifos reales).
bool usarFuentesReales = true;

const telefonoChico = Size(360, 640);
const telefonoGrande = Size(412, 915);
const tamanos = [telefonoChico, telefonoGrande];
const escalas = [1.0, 2.0];

var _fuentesCargadas = false;

Future<void> cargarFuentes(WidgetTester tester) async {
  if (_fuentesCargadas || !usarFuentesReales) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final iconos = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (iconos.existsSync()) {
        final bytes = iconos.readAsBytesSync();
        final cargador = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await cargador.load();
        break;
      }
    }
  });
  _fuentesCargadas = true;
}

/// Una captura PNG de todo lo que se ve (hojas modales incluidas) en `.dart_tool/qa_capturas/`.
Future<void> capturar(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final tamano = tester.view.physicalSize / tester.view.devicePixelRatio;
    final img = await capa.toImage(Offset.zero & tamano);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/432_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
