// Arnés de los tests de QA de la vista 09 «Baja de ubicación» (HU-UBI-005, #205): carga las fuentes
// reales del proyecto (sin ellas `flutter_test` pinta cajas Ahem y las medidas de layout mienten) y
// saca capturas PNG a `.dart_tool/qa_capturas/` (gitignored: nunca se commitean).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// La raíz de la captura: envuelve la app entera (la hoja y el aviso viven dentro).
final raizCaptura205 = GlobalKey();

/// Tamaños lógicos de la matriz de QA: el chico y el grande.
const telefonoChico205 = Size(360, 640);
const telefonoGrande205 = Size(412, 915);

/// Carga Inter, SourceSerif4 y JetBrainsMono de `assets/fonts/` y los íconos de Material.
Future<void> cargarFuentes205(WidgetTester tester) async {
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
}

/// Una captura PNG de [raizCaptura205] en `.dart_tool/qa_capturas/205_<nombre>.png`.
Future<void> capturar205(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raizCaptura205));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/205_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Contraste WCAG entre dos colores opacos.
double contraste205(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final claro = la > lb ? la : lb;
  final oscuro = la > lb ? lb : la;
  return (claro + 0.05) / (oscuro + 0.05);
}

/// Ningún texto visible se sale de la pantalla por los costados (un texto cortado a la derecha es lo
/// que deja el `Row` sin `Expanded` con el texto a 200 %).
void expectSinTextoFueraDeLosCostados205(WidgetTester tester, Size tamano) {
  for (final e in find.byType(RichText).evaluate()) {
    final render = e.renderObject;
    if (render is! RenderBox || !render.attached || !render.hasSize) continue;
    // Una fila que se desplaza de costado (los chips de filtros) puede tener texto más allá del borde.
    var enDesplazamientoHorizontal = false;
    e.visitAncestorElements((a) {
      final w = a.widget;
      if (w is Scrollable && w.axis == Axis.horizontal) enDesplazamientoHorizontal = true;
      return !enDesplazamientoHorizontal;
    });
    if (enDesplazamientoHorizontal) continue;
    final r = render.localToGlobal(Offset.zero) & render.size;
    expect(
      r.left >= -0.5 && r.right <= tamano.width + 0.5,
      isTrue,
      reason: 'un texto se sale de la pantalla: ${(e.widget as RichText).text.toPlainText()} $r',
    );
  }
}
