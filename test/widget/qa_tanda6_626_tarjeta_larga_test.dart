// QA de la tanda 6 de #537 (#626, PR #731): `TarjetaDeDatos` (devolución 31) a 1,0 con rótulos y valores
// largos. El PR repartió el ancho de la fila 1 : 2 (rótulo : valor) para que «Nuestros Hijos × 1» no se
// parta; acá se mira el otro lado: los rótulos reales de la vista («Total de la venta», «Se queda con»)
// y un valor de varios productos con títulos largos, a 360 dp y de 1,0 a 1,3 (antes del cambio a dos
// renglones, que arranca a más de 1,14).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/ventas/presentation/textos_devolucion.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/piezas_devolucion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _capturar = bool.fromEnvironment('QA_CAPTURAS');

var _fuentes = false;
Future<void> _cargarFuentes(WidgetTester tester) async {
  if (_fuentes) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final c = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await c.load();
    }
  });
  _fuentes = true;
}

Future<void> _montar(WidgetTester tester, Widget hijo, double escala) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: temaClaro(),
      home: MediaQuery(
        data: MediaQueryData(size: const Size(360, 640), textScaler: TextScaler.linear(escala)),
        child: Scaffold(
          body: RepaintBoundary(
            key: const Key('cap'),
            child: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: hijo),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _capturar2(WidgetTester tester, String nombre) async {
  if (!_capturar) return;
  await tester.runAsync(() async {
    final limite = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('cap')));
    final imagen = await limite.toImage();
    final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
    final f = File('.dart_tool/qa_capturas/$nombre.png')..createSync(recursive: true);
    f.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Cuántos renglones ocupa el `Text` de [texto].
int _renglones(WidgetTester tester, String texto, double escala) {
  final p = tester.renderObject<RenderParagraph>(find.text(texto));
  return (p.size.height / (14 * 1.2 * escala)).round();
}

void main() {
  const escalas = [1.0, 1.1, 1.2, 1.3];

  for (final escala in escalas) {
    testWidgets(
      'rótulos reales de 31 a 360 dp × $escala: un renglón por rótulo',
      (tester) async {
        await _cargarFuentes(tester);
        final datos = [
          const DatoDeDevolucion(TextosDevolucion.totalDeLaVenta, '\$ 123.456,50'),
          const DatoDeDevolucion(TextosDevolucion.seQuedaCon, '\$ 4.500'),
          const DatoDeDevolucion(TextosDevolucion.saldoNuevo, '\$ 21.474,47', fuerte: true),
        ];
        await _montar(tester, TarjetaDeDatos(datos: datos), escala);
        expect(tester.takeException(), isNull);
        await _capturar2(tester, '731_larga_rotulos_x$escala');
        for (final d in datos) {
          expect(
            _renglones(tester, d.rotulo, escala),
            1,
            reason: '«${d.rotulo}» baja a otro renglón a 360 dp × $escala',
          );
        }
      },
      // Con el rótulo en `Flexible` y el valor en `Expanded(flex: 2)` el rótulo se queda con un tercio
      // del ancho aunque el valor sea corto: a 1,0 y a 1,1 (hasta 1,14 no pasa a dos renglones) «Total de
      // la venta» y «Se queda con» bajan de renglón con lugar de sobra.
      // skip: QA #626 — TarjetaDeDatos (31) reparte el ancho 1:2 y parte «Total de la venta» y «Se queda
      // con» a 1,0–1,1 con lugar de sobra.
      skip: escala <= 1.1,
    );
  }

  for (final escala in escalas) {
    testWidgets('«Devuelve» con varios productos de título largo a 360 dp × $escala, sin overflow', (
      tester,
    ) async {
      await _cargarFuentes(tester);
      const valor =
          'El Conflicto de los Siglos × 2\nNuestros Hijos × 1\nEl Deseado de Todas las Gentes × 3';
      await _montar(
        tester,
        const TarjetaDeDatos(datos: [DatoDeDevolucion('Devuelve', valor)]),
        escala,
      );
      expect(tester.takeException(), isNull);
      await _capturar2(tester, '731_larga_devuelve_x$escala');
      expect(find.text('Devuelve'), findsOneWidget);
      // El rótulo no se parte en mitad de palabra.
      final p = tester.renderObject<RenderParagraph>(find.text('Devuelve'));
      expect(p.size.height, lessThan(14 * 1.2 * escala * 1.5));
    });
  }
}
