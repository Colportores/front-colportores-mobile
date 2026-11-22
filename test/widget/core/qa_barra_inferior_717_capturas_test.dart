// Capturas de QA de #717 (PR #719): las hojas con una barra de navegación simulada de 48 dp encima
// (la tira gris del pie). Solo con `--dart-define=QA_CAPTURAS=true`; salen a `.dart_tool/qa_capturas`
// (fuera del repo) y no se commitean.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/configuracion/presentation/widgets/hoja_cerrar_sesion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:colportores_mobile/features/respaldo/presentation/widgets/hoja_recuperar_respaldo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OffsetLayer;
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/espacios_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../mapa/hoja_espacios_arnes.dart';
import '../mapa/lista_ubicaciones_arnes.dart';

const _capturar = bool.fromEnvironment('QA_CAPTURAS');
const _barra = 48.0;

Future<void> _fuentes(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      await (FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
    }
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final iconos = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (iconos.existsSync()) {
        final bytes = iconos.readAsBytesSync();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
        break;
      }
    }
  });
}

/// Guarda la pantalla entera (hojas modales incluidas) con la barra simulada de 48 dp: una tira
/// gris pegada al borde de abajo, pintada encima.
Future<void> _guardar(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final capa = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final tamano = tester.view.physicalSize;
    final imagen = await capa.toImage(Offset.zero & tamano);
    final grabador = ui.PictureRecorder();
    Canvas(grabador)
      ..drawImage(imagen, Offset.zero, Paint())
      ..drawRect(
        Rect.fromLTWH(0, tamano.height - _barra, tamano.width, _barra),
        Paint()..color = const Color(0xCC444444),
      );
    final dibujo = await grabador.endRecording().toImage(
      tamano.width.toInt(),
      tamano.height.toInt(),
    );
    final bytes = await dibujo.toByteData(format: ui.ImageByteFormat.png);
    final archivo = File('.dart_tool/qa_capturas/$nombre.png')..createSync(recursive: true);
    archivo.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void _pantalla(WidgetTester tester, Size tamano) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  tester.view.viewPadding = const FakeViewPadding(bottom: _barra);
  tester.view.padding = const FakeViewPadding(bottom: _barra);
  addTearDown(tester.view.reset);
}

void main() {
  for (final escala in [1.0, 2.0]) {
    final e = escala == 1 ? '1x' : '2x';
    testWidgets('captura: cerrar sesión y recuperar respaldo, 360x640 texto $e', (tester) async {
      await _fuentes(tester);
      for (final caso in ['cerrar_sesion', 'recuperar_respaldo']) {
        _pantalla(tester, const Size(360, 640));
        await tester.pumpWidget(
          MaterialApp(
            theme: temaClaro(),
            builder: (context, hijo) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
              child: hijo!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    key: const Key('abrir'),
                    onPressed: () => caso == 'cerrar_sesion'
                        ? mostrarHojaCerrarSesion(context, pendientes: 4, cerrar: () async => true)
                        : mostrarHojaRecuperarRespaldo(context, cuentaDrive: 'ana@example.com'),
                    child: const Text('Abrir'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('abrir')));
        await tester.pumpAndSettle();
        await _guardar(tester, '717_${caso}_360x640_$e');
        await tester.pumpWidget(const SizedBox());
      }
    }, skip: !_capturar);

    testWidgets('captura: hoja de la casa y de una ubicación, 360x640 texto $e', (tester) async {
      await _fuentes(tester);
      _pantalla(tester, const Size(360, 640));
      await montarLista(
        tester,
        repo: RepoListaFalso([
          filaLista('a', calle: 'Av. Italia', numero: '1234', metrosAlNorte: 40),
        ]),
        casaAbreSuHoja: true,
        tamano: const Size(360, 640),
        escala: escala,
      );
      await tester.tap(find.textContaining('Av. Italia'));
      await asentarLista(tester, 14);
      await _guardar(tester, '717_hoja_casa_360x640_$e');
    }, skip: !_capturar);

    testWidgets('captura: hoja de la ubicación con deptos, 360x640 texto $e', (tester) async {
      await _fuentes(tester);
      _pantalla(tester, const Size(360, 640));
      await montarHoja(
        tester,
        tamano: const Size(360, 640),
        escala: escala,
        espacios: [
          for (var i = 1; i <= 12; i++)
            espacioDe('e$i', '${100 + i}', piso: '${1 + i ~/ 4}', orden: i),
        ],
      );
      expect(find.byKey(ClavesHojaUbicacion.hoja), findsOneWidget);
      await _guardar(tester, '717_hoja_ubicacion_360x640_$e');
    }, skip: !_capturar);
  }
}
