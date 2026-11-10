// QA #674 (issue #670, HU-UBI-003): la geometría de lo que el seguimiento pone en pantalla, con las
// fuentes reales (con Ahem el texto ocupa el doble y las medidas no valen). El aviso de corte del
// seguimiento («Dejamos de seguir tu ubicación…») sale como SnackBar sobre el mapa: tiene que verse
// entero, con su acción a mano, y no dejar a Ana sin el botón con el que se vuelve a seguir.
// Las capturas (`--dart-define=QA_CAPTURAS=true`) van a `.dart_tool/qa_capturas/` y no se commitean.
import 'dart:io';
import 'dart:typed_data' show ByteData;
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart' show MotivoSinGps;
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/modo_seguimiento.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/ubicacion_colportor_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OffsetLayer, RenderParagraph;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/lista_ubicaciones_falsos.dart';
import 'mapa_ubicaciones_arnes.dart';
import 'mapa_ubicaciones_page_test.dart' show canvas;

/// Los tests de un hallazgo se saltan (con el motivo en un comentario); `--dart-define=QA_HALLAZGOS=true`
/// los corre. `skip` de `testWidgets` es un `bool?`, no un texto.
const _sinHallazgos = !bool.fromEnvironment('QA_HALLAZGOS');
const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');

const _tamanos = [Size(360, 640), Size(412, 915)];
const _escalas = [1.0, 2.0];
const _adelante = Coordenadas(lat: -34.88700, lon: -56.13024);

bool _dentro(Rect caja, Size t) =>
    caja.left >= -0.01 &&
    caja.top >= -0.01 &&
    caja.right <= t.width + 0.01 &&
    caja.bottom <= t.height + 0.01;

/// Los casos donde el aviso cubre el botón de ubicación: con el texto a 2,0 en los dos tamaños, y a
/// 360×640 con «Activar GPS» (el aviso sube con la acción).
bool _tapaElBoton(Size tamano, double escala, MotivoSinGps motivo) =>
    escala > 1.5 || (tamano.height < 700 && motivo != MotivoSinGps.sinSenal);

/// Carga los íconos de Material; sin esto el ícono del botón sale como un cuadrado. Los toma del SDK
/// (`<sdk>/bin/cache/artifacts/material_fonts`) o, si el SDK no los trae, de la copia que vienen en
/// los paquetes de devtools del caché de pub.
Future<void> cargarIconosMaterial() async {
  final sdk = File(Platform.resolvedExecutable).parent.parent.parent.path;
  final candidatos = <File>[
    File('$sdk/material_fonts/MaterialIcons-Regular.otf'),
    for (final e in Directory('/pub-cache/hosted/pub.dev').listSync())
      File('${e.path}/extension/devtools/build/assets/fonts/MaterialIcons-Regular.otf'),
  ];
  final archivo = candidatos.where((f) => f.existsSync()).firstOrNull;
  if (archivo == null) return;
  final bytes = archivo.readAsBytesSync();
  final cargador = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(bytes.buffer)));
  await cargador.load();
}

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_conCapturas) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/674_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

Future<MontajeMapaUbicaciones> _montarYCortar(
  WidgetTester tester, {
  required Size tamano,
  required double escala,
  required MotivoSinGps motivo,
}) async {
  await tester.runAsync(cargarFuentesReales);
  final m = await montarMapaUbicaciones(
    tester,
    repo: RepoListaFalso(canvas()),
    tamano: tamano,
    escala: escala,
  );
  for (var i = 0; i < 2; i++) {
    await tester.tap(botonMiUbicacion);
    await asentarLista(tester);
  }
  m.gps.moverse(const LecturaGps(coordenadas: _adelante, precisionMetros: 5, rumboGrados: 90));
  await asentarLista(tester);
  m.gps.fallarElSeguimiento(motivo);
  await asentarLista(tester);
  return m;
}

void main() {
  group('el aviso de corte: se ve entero y con su acción a mano', () {
    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        for (final motivo in MotivoSinGps.values) {
          final caso =
              '${tamano.width.toInt()}x${tamano.height.toInt()} a $escala · ${motivo.name}';

          testWidgets('$caso: texto sin cortar, dentro de la pantalla y «Activar GPS» a 48 dp o '
              'más', (tester) async {
            await _montarYCortar(tester, tamano: tamano, escala: escala, motivo: motivo);

            final aviso = find.text(TextosMapaUbicaciones.seguimientoCortado);
            expect(aviso, findsOneWidget);
            expect(_dentro(tester.getRect(aviso), tamano), isTrue, reason: 'texto dentro');
            expect(tester.renderObject<RenderParagraph>(aviso).didExceedMaxLines, isFalse);
            expect(_dentro(tester.getRect(find.byType(SnackBar)), tamano), isTrue);
            if (motivo != MotivoSinGps.sinSenal) {
              final accion = find.widgetWithText(SnackBarAction, TextosMapaUbicaciones.activarGps);
              expect(accion, findsOneWidget);
              expect(tester.getSize(accion).height, greaterThanOrEqualTo(48));
              expect(accion.hitTestable(), findsOneWidget, reason: 'la acción se puede tocar');
            }
            await _capturar(tester, 'aviso_${tamano.width.toInt()}_${escala}_${motivo.name}');
            expect(tester.takeException(), isNull);
          });

          // skip (los casos que cubre): QA #674 — el aviso de corte tapa el botón de ubicación, que es
          // el que el propio aviso manda a tocar («…tocá el botón para volver a seguirte»).
          testWidgets(
            '$caso: el aviso no tapa el botón de ubicación',
            (tester) async {
              await _montarYCortar(tester, tamano: tamano, escala: escala, motivo: motivo);

              expect(
                tester.getRect(find.byType(SnackBar)).overlaps(tester.getRect(botonMiUbicacion)),
                isFalse,
              );
              expect(botonMiUbicacion.hitTestable(), findsOneWidget);
            },
            skip: _tapaElBoton(tamano, escala, motivo) && _sinHallazgos,
          );
        }
      }
    }

    // skip: QA #674 — a 360×640 con el texto a 2,0 el aviso de corte con «Activar GPS» mide ~495 dp de
    // 640: cubre el mapa, la hoja y el botón con el que se vuelve a seguir.
    for (final motivo in [MotivoSinGps.permisoDenegado, MotivoSinGps.servicioApagado]) {
      testWidgets('360x640 a 2.0 · ${motivo.name}: el aviso no cubre el botón de ubicación ni '
          'más de la mitad de la pantalla', (tester) async {
        await _montarYCortar(tester, tamano: const Size(360, 640), escala: 2, motivo: motivo);

        final aviso = tester.getRect(find.byType(SnackBar));
        expect(aviso.height, lessThanOrEqualTo(640 / 2), reason: 'el aviso no tapa el mapa');
        expect(aviso.overlaps(tester.getRect(botonMiUbicacion)), isFalse);
        expect(botonMiUbicacion.hitTestable(), findsOneWidget);
      }, skip: _sinHallazgos);
    }
  });

  group('el seguimiento de Ana entre pestañas y avisos', () {
    testWidgets('tras un corte, volver a tocar el botón sigue a Ana de nuevo y el aviso viejo no '
        'se queda tapando', (tester) async {
      final m = await _montarYCortar(
        tester,
        tamano: const Size(412, 915),
        escala: 1,
        motivo: MotivoSinGps.sinSenal,
      );
      expect(
        contenedorDeLaPestana(tester).read(ubicacionColportorProvider).modo,
        ModoSeguimiento.libre,
      );

      await tester.tap(botonMiUbicacion);
      await asentarLista(tester);

      expect(m.gps.siguiendo, isTrue);
      expect(
        contenedorDeLaPestana(tester).read(ubicacionColportorProvider).modo,
        ModoSeguimiento.seguir,
      );
    });
  });
  group('capturas de los tres modos del botón (solo con QA_CAPTURAS)', () {
    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        testWidgets('${tamano.width.toInt()}x${tamano.height.toInt()} a $escala', (tester) async {
          await tester.runAsync(cargarFuentesReales);
          await tester.runAsync(cargarIconosMaterial);
          await montarMapaUbicaciones(
            tester,
            repo: RepoListaFalso(canvas()),
            tamano: tamano,
            escala: escala,
          );
          for (final modo in ModoSeguimiento.values) {
            await _capturar(tester, 'modo_${tamano.width.toInt()}_${escala}_${modo.name}');
            await tester.tap(botonMiUbicacion);
            await asentarLista(tester);
          }
        }, skip: !_conCapturas);
      }
    }
  });
}
