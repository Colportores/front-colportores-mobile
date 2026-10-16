// QA del PR #351 (#313 y #318, vista 14), con la tipografía real del proyecto: con las fuentes de
// prueba de `flutter_test` cada letra mide un cuadrado y los íconos salen como cajas, así que la
// geometría y las capturas van en un archivo aparte (las fuentes cargadas valen para todo el archivo).
//
// - Siempre: el aviso de lectura lenta, A05 con la sesión abierta y el teclado abierto, medidos con
//   la tipografía real.
// - Solo con `--dart-define=QA_CAPTURAS=true`: una captura PNG de cada estado en `.dart_tool/
//   qa_capturas/` (carpeta ignorada por git: las capturas no se commitean).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_vista14_351_arnes.dart';

const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

/// Las fuentes del proyecto y los íconos de Material.
Future<void> _cargarFuentes(WidgetTester tester) => tester.runAsync(() async {
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

Future<void> _capturar(WidgetTester tester, String nombre) => tester.runAsync(() async {
  final render = tester.renderObject<RenderRepaintBoundary>(
    find
        .ancestor(of: find.byType(RecuperacionPasswordPage), matching: find.byType(RepaintBoundary))
        .first,
  );
  final img = await render.toImage();
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
  final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
  File('${dir.path}/351_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
});

String _archivo(String estado, Size tam, double texto) =>
    '${estado.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_${tam.width.toInt()}x${tam.height.toInt()}_x${texto.toInt()}';

void main() {
  group('QA #351 · con la tipografía real', () {
    testWidgets('el aviso de lectura lenta a 360×640 y texto al 200 %: entero, sin desborde y con '
        'el botón a mano', (tester) async {
      await _cargarFuentes(tester);
      final estado = estadosQa.firstWhere((e) => e.nombre == 'A01 con el aviso de lectura lenta');
      await estado.armar(tester, const Size(360, 640), 2);

      expect(tester.takeException(), isNull);
      final aviso = tester.getRect(find.text(avisoLentaQa));
      expect(aviso.left, greaterThanOrEqualTo(0));
      expect(aviso.right, lessThanOrEqualTo(360));
      await tester.ensureVisible(enviarQa);
      expect(tester.getRect(enviarQa).bottom, lessThanOrEqualTo(640));
    });

    testWidgets(
      'A05 con la sesión abierta, texto al 300 % en 360×640: «Volver» se alcanza entero',
      (tester) async {
        await _cargarFuentes(tester);
        final estado = estadosQa.firstWhere((e) => e.nombre == 'A05 éxito con la sesión abierta');
        await estado.armar(tester, const Size(360, 640), 3);

        await tester.ensureVisible(volverQa);
        await tester.pump();
        final r = tester.getRect(volverQa);
        expect(tester.takeException(), isNull);
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(360));
        expect(r.bottom, lessThanOrEqualTo(640));
        expect(find.text('Volver'), findsOneWidget);
      },
    );

    for (final texto in [1.0, 2.0]) {
      testWidgets(
        'con el teclado abierto (300 px) en 360×640 y texto al ${(texto * 100).toInt()} %: '
        'el campo enfocado queda a la vista y el botón se alcanza',
        (tester) async {
          await _cargarFuentes(tester);
          await montarQa(tester, remote: remotoQa(), tamano: const Size(360, 640), texto: texto);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.tap(llaveQa('recuperacion_password_email'));
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          const libre = 640 - 300;
          final campo = tester.getRect(llaveQa('recuperacion_password_email'));
          expect(campo.top, greaterThanOrEqualTo(0));
          expect(
            campo.bottom,
            lessThanOrEqualTo(libre),
            reason: 'el campo no queda detrás del teclado',
          );
          await tester.ensureVisible(enviarQa);
          await tester.pump();
          expect(tester.getRect(enviarQa).bottom, lessThanOrEqualTo(libre));
        },
      );
    }
  });

  if (_conCapturas) {
    group('QA #351 · capturas (solo con QA_CAPTURAS=true)', () {
      for (final estado in estadosQa) {
        for (final (tam, texto) in [
          (const Size(360, 640), 1.0),
          (const Size(360, 640), 2.0),
          (const Size(412, 915), 1.0),
        ]) {
          testWidgets('${estado.nombre} ${nombreTamQa(tam)} x$texto', (tester) async {
            await _cargarFuentes(tester);
            await estado.armar(tester, tam, texto);
            await tester.pump(const Duration(milliseconds: 300));
            await _capturar(tester, _archivo(estado.nombre, tam, texto));
          });
        }
      }

      testWidgets('A01 con el teclado abierto 360x640 x1', (tester) async {
        await _cargarFuentes(tester);
        await montarQa(tester, remote: remotoQa(), tamano: const Size(360, 640));
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.tap(llaveQa('recuperacion_password_email'));
        await tester.pumpAndSettle();
        await _capturar(tester, 'a01_teclado_360x640_x1');
      });
    });
  }
}
