// QA de #145 (HU-UBI-013, vista 22 grupo A): el contraste real de los textos de las tarjetas de la
// sección «COBRANZA» (WCAG 1.4.3: 4,5:1 para texto chico, también el de un botón activo).
//
// `textContrastGuideline` no alcanza acá: mide el color más frecuente del nodo contra el más claro y la
// tarjeta «dada de baja» (22A·08) pinta todo con `Opacity(.6)`. Este test lee los píxeles ya pintados
// de cada texto. Con la fuente de prueba (Ahem) cada letra es un bloque macizo del color del texto,
// así que el píxel más oscuro de la caja del texto es su color real, ya mezclado con la atenuación.
import 'dart:math' as math;
import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/mapa/domain/entities/estado_ubicacion_alternativa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ubicacion_alternativa.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/qa_ubicacion_alternativa_145_arnes.dart';

double _luminancia(int r, int g, int b) {
  double c(int v) {
    final x = v / 255;
    return x <= 0.03928 ? x / 12.92 : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * c(r) + 0.7152 * c(g) + 0.0722 * c(b);
}

/// La relación de contraste entre el píxel más oscuro y el más claro dentro de [caja] (con 4 px de
/// margen a los lados: una palabra sola con Ahem es un bloque macizo y sin fondo no hay contra qué medir).
Future<double> _contraste(WidgetTester tester, Rect texto) async {
  final caja = Rect.fromLTRB(texto.left - 4, texto.top, texto.right + 4, texto.bottom);
  final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
  final tamano = tester.view.physicalSize;
  late ByteData bytes;
  late int ancho;
  await tester.runAsync(() async {
    final img = await capa.toImage(Offset.zero & tamano, pixelRatio: 1);
    ancho = img.width;
    bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });
  var oscuro = 2.0;
  var claro = -1.0;
  final x0 = caja.left.floor().clamp(0, ancho - 1);
  final x1 = caja.right.ceil().clamp(0, ancho);
  final y0 = caja.top.floor().clamp(0, tamano.height.toInt() - 1);
  final y1 = caja.bottom.ceil().clamp(0, tamano.height.toInt());
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final o = (y * ancho + x) * 4;
      final l = _luminancia(bytes.getUint8(o), bytes.getUint8(o + 1), bytes.getUint8(o + 2));
      if (l < oscuro) oscuro = l;
      if (l > claro) claro = l;
    }
  }
  return (claro + 0.05) / (oscuro + 0.05);
}

/// `--dart-define=QA_HALLAZGOS=true` corre los tests de hallazgos (los que llevan `skip`).
const _hallazgos = bool.fromEnvironment('QA_HALLAZGOS');

void main() {
  const tamano = Size(412, 915);

  Future<void> montar(WidgetTester tester, EstadoUbicacionAlternativa estado) async {
    await montarFicha(tester, mundo145(estado: estado), tamano: tamano);
    await irALaSeccion145(tester);
    await tester.pump(const Duration(milliseconds: 600));
  }

  Finder textoEn(Finder tarjeta, String texto) =>
      find.descendant(of: tarjeta, matching: find.text(texto));

  group('tarjeta vigente (22A·06): texto a todo color', () {
    final vigente = find.byKey(ClavesAlternativa.vigente);
    for (final texto in ['SE COBRA ACÁ', 'Av. Italia 2810', 'Negocio', 'Quitar']) {
      testWidgets('«$texto» tiene al menos 4,5:1', (tester) async {
        await montar(tester, UbicacionAlternativaVigente(italia145));
        final ratio = await _contraste(tester, tester.getRect(textoEn(vigente, texto)));
        expect(ratio, greaterThanOrEqualTo(4.5), reason: '$texto: ${ratio.toStringAsFixed(2)}:1');
      });
    }
  });

  group('tarjeta dada de baja (22A·08): el 60 % de opacidad del canvas', () {
    final deBaja = find.byKey(ClavesAlternativa.deBaja);
    final estado = UbicacionAlternativaDeBaja('ub-2', ubicacion: italiaDeBaja145);

    // «Quitar» es un botón activo; «DADA DE BAJA» y el detalle son información. Los tres quedan en
    // ~3:1 (rojo y gris al 60 % sobre blanco), bajo el 4,5:1 de AA.
    group(
      'texto a 4,5:1',
      skip: _hallazgos
          ? false
          : 'QA #145: la tarjeta dada de baja pinta rótulo, tipo y «Quitar» al 60 % de opacidad: '
                '~3:1, bajo AA (1.4.3)',
      () {
        for (final texto in ['DADA DE BAJA', 'Quitar', 'Negocio']) {
          testWidgets('«$texto» tiene al menos 4,5:1', (tester) async {
            await montar(tester, estado);
            final ratio = await _contraste(tester, tester.getRect(textoEn(deBaja, texto)));
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason: '$texto: ${ratio.toStringAsFixed(2)}:1',
            );
          });
        }
      },
    );
  });
}
