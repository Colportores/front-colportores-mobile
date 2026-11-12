// Arnés de los tests de QA de «Reactivar una baja» (HU-UBI-005, #334, PR #366): reusa las fuentes
// reales y las medidas del arnés de #205 y le suma las capturas de esta vista y la matriz de tamaños
// completa (320×568, 360×640, 360×740, 390×844 y 412×915).
//
// Las capturas van a `.dart_tool/qa_capturas/334_*.png` (gitignored: nunca se commitean).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

export 'qa_baja_205_arnes.dart'
    show cargarFuentes205, contraste205, expectSinTextoFueraDeLosCostados205;

/// La raíz de la captura: envuelve la app entera (la hoja y el aviso viven dentro).
final raizCaptura334 = GlobalKey();

/// Los cinco tamaños lógicos de la matriz.
const t320x568 = Size(320, 568);
const t360x640 = Size(360, 640);
const t360x740 = Size(360, 740);
const t390x844 = Size(390, 844);
const t412x915 = Size(412, 915);

/// Tamaños × escalas de texto de la matriz de QA.
const matriz334 = <(Size, double)>[
  (t320x568, 1.0),
  (t320x568, 2.0),
  (t360x640, 1.0),
  (t360x640, 2.0),
  (t360x740, 1.0),
  (t360x740, 2.0),
  (t390x844, 1.0),
  (t390x844, 2.0),
  (t412x915, 1.0),
  (t412x915, 2.0),
];

/// «320x568_x2.0».
String sufijo334(Size tamano, double escala) =>
    '${tamano.width.toInt()}x${tamano.height.toInt()}_x$escala';

/// Una captura PNG de [raizCaptura334] en `.dart_tool/qa_capturas/334_<nombre>.png`.
Future<void> capturar334(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raizCaptura334));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/334_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
