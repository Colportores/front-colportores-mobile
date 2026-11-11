// Arnés del QA de #692 (vista 41, 41E·03, 03B y 03C): las escenas del botón de ubicación en sus tres
// modos (con el rótulo de 2 s, la brújula y el cono), listas para medirlas en los tamaños y escalas
// del QA, y la captura de cada una (solo con `--dart-define=QA_CAPTURAS=true`).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart' show GpsFalso;
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/mapa_descargas_arnes.dart';
import 'mapa_ubicaciones_arnes.dart';
import 'mapa_ubicaciones_page_test.dart' show canvas, gpsSinPermiso;

export 'mapa_ubicaciones_arnes.dart';

const capturas692 = bool.fromEnvironment('QA_CAPTURAS');

const adelante692 = Coordenadas(lat: -34.88700, lon: -56.13024);
const masAdelante692 = Coordenadas(lat: -34.88650, lon: -56.13000);

LecturaGps lectura692(Coordenadas punto, {double? rumbo}) =>
    LecturaGps(coordenadas: punto, precisionMetros: 5, rumboGrados: rumbo);

final rotulo692 = find.byKey(ClavesMapaUbicaciones.rotuloModo);
final brujula692 = find.byKey(ClavesMapaUbicaciones.brujula);
final cono692 = find.byKey(ClavesMapaUbicaciones.cono);

/// Carga Inter, SourceSerif4 y JetBrainsMono de `assets/fonts/` y los íconos de Material (sin las
/// fuentes reales `flutter_test` pinta cajas y el ancho de los textos es falso).
Future<void> cargarFuentes692(WidgetTester tester) async {
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

/// Una captura PNG de la pantalla entera en `.dart_tool/qa_capturas/692_<nombre>.png`.
Future<void> capturar692(WidgetTester tester, String nombre) async {
  if (!capturas692) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File(
      '${dir.path}/692_${nombre.replaceAll(RegExp(r'[^A-Za-z0-9.-]+'), '_')}.png',
    ).writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

Future<void> tocarBoton692(WidgetTester tester) async {
  await tester.tap(botonMiUbicacion);
  await asentarLista(tester);
}

Future<void> moverse692(WidgetTester tester, GpsFalso gps, LecturaGps lectura) async {
  gps.moverse(lectura);
  await asentarLista(tester);
}

typedef Escena692 =
    Future<MontajeMapaUbicaciones> Function(WidgetTester tester, Size tamano, double escala);

Future<MontajeMapaUbicaciones> _montar(
  WidgetTester tester,
  Size tamano,
  double escala, {
  GpsFalso? gps,
  ArnesMapa? arnes,
}) => montarMapaUbicaciones(
  tester,
  repo: RepoListaFalso(canvas()),
  gps: gps,
  arnes: arnes,
  ambito: arnes == null ? null : ambitoMontevideo,
  tamano: tamano,
  escala: escala,
);

/// Cada estado del botón de ubicación, armado como lo vería la colportora. En los que el rótulo debe
/// estar a la vista no se deja pasar el tiempo.
final escenas692 = <String, Escena692>{
  '41E·03 libre': (t, tam, e) => _montar(t, tam, e),
  '41E·03B seguir, con el rótulo': (t, tam, e) async {
    final m = await _montar(t, tam, e);
    await tocarBoton692(t);
    return m;
  },
  '41E·03C girar sin rumbo, con el rótulo': (t, tam, e) async {
    final m = await _montar(t, tam, e);
    await tocarBoton692(t);
    await tocarBoton692(t);
    return m;
  },
  '41E·03C girar con rumbo: cono y brújula, con el rótulo': (t, tam, e) async {
    final m = await _montar(t, tam, e);
    await tocarBoton692(t);
    await tocarBoton692(t);
    await moverse692(t, m.gps, lectura692(adelante692, rumbo: 120));
    return m;
  },
  '41E·03C girar con rumbo: cono y brújula, sin rótulo': (t, tam, e) async {
    final m = await _montar(t, tam, e);
    await tocarBoton692(t);
    await tocarBoton692(t);
    await moverse692(t, m.gps, lectura692(adelante692, rumbo: 120));
    await t.pump(MedidasBotonUbicacion.duracionRotulo);
    await t.pump(const Duration(milliseconds: 100));
    return m;
  },
  '41E·03 vuelta a libre, con el rótulo': (t, tam, e) async {
    final m = await _montar(t, tam, e);
    await tocarBoton692(t);
    await tocarBoton692(t);
    await tocarBoton692(t);
    return m;
  },
  '41E·03C libre con el mapa girado a mano: brújula': (t, tam, e) async {
    final m = await _montar(t, tam, e);
    await tocarBoton692(t);
    await tocarBoton692(t);
    await moverse692(t, m.gps, lectura692(adelante692, rumbo: 135));
    m.mapa.moverPorGesto(m.mapa.camara!.conCentro(const Coordenadas(lat: -34.90, lon: -56.15)));
    await asentarLista(t);
    await t.pump(MedidasBotonUbicacion.duracionRotulo);
    await t.pump(const Duration(milliseconds: 100));
    return m;
  },
  '41E·03 sin GPS (botón apagado)': (t, tam, e) => _montar(t, tam, e, gps: gpsSinPermiso()),
  '41E·03C girar con rumbo y aviso «Sin conexión»': (t, tam, e) async {
    final m = await _montar(
      t,
      tam,
      e,
      arnes: ArnesMapa(conexion: TipoConexion.sinConexion, catalogo: [paqueteMontevideo]),
    );
    await tocarBoton692(t);
    await tocarBoton692(t);
    await moverse692(t, m.gps, lectura692(adelante692, rumbo: 120));
    return m;
  },
};

const tamanos692 = {'360x640': Size(360, 640), '412x915': Size(412, 915)};
