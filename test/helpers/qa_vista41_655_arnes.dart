// Arnés del QA de #655 (vista 41, entrega 1: alta sobre el mapa 41A y duplicado 41B). Monta la pestaña
// «Mapa» con el alta real a cualquier tamaño y escala, lleva el alta a cada uno de los 11 artboards
// y saca capturas (solo con `--dart-define=QA_CAPTURAS=true`, a `.dart_tool/qa_capturas/`).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/duplicado_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_principal_provider.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/alta_sobre_el_mapa.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/mapa_ubicaciones_arnes.dart';
import 'alta_ubicacion_falsos.dart';
import 'lista_ubicaciones_falsos.dart';
import 'zonas_falsas.dart';

const conCapturas655 = bool.fromEnvironment('QA_CAPTURAS');

/// Los hallazgos con `skip`: `--dart-define=QA_HALLAZGOS=true` los corre para verlos fallar.
const verHallazgos655 = bool.fromEnvironment('QA_HALLAZGOS');

/// Las fuentes reales: `false` en el archivo de contraste (con ellas `textContrastGuideline` da
/// falsos negativos).
bool usarFuentesReales655 = true;

const telefonoChico655 = Size(360, 640);
const telefonoGrande655 = Size(412, 915);
const tamanos655 = [telefonoChico655, telefonoGrande655];
const escalas655 = [1.0, 2.0];

/// Unos 40 m al este de Av. Italia: ahí el mapa dice «Mataojo 2047».
const mataojo655 = Coordenadas(lat: -34.88761, lon: -56.12980);

final principal655 = find.byKey(ClavesAltaMapa.principal);
final secundario655 = find.byKey(ClavesAltaMapa.secundario);
final hojaAlta655 = find.byKey(ClavesAltaMapa.hoja);
final crearIgual655 = find.byKey(ClavesAltaMapa.crearIgual);
final justificacion655 = find.byKey(ClavesAltaMapa.justificacion);

DireccionDelPunto? direccion655(Coordenadas p) =>
    (p.lat - puntoItalia.lat).abs() < 1e-6 && (p.lon - puntoItalia.lon).abs() < 1e-6
    ? const DireccionDelPunto(calle: 'Grecia', numero: '3307')
    : const DireccionDelPunto(calle: 'Mataojo', numero: '2047');

var _fuentesCargadas = false;

Future<void> cargarFuentes655(WidgetTester tester) async {
  if (_fuentesCargadas || !usarFuentesReales655) return;
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

/// Lo que un test del alta necesita después de montarla.
final class Alta655 {
  Alta655(this.m, this.repo, this.ciudades);

  final MontajeMapaUbicaciones m;
  final RepoAltaFalso repo;
  final CiudadesFalsas ciudades;
}

Future<Alta655> montar655(
  WidgetTester tester, {
  GpsFalso? gps,
  RepoAltaFalso? repo,
  GeocodificadorFalso? geocodificador,
  CiudadesFalsas? ciudades,
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  await cargarFuentes655(tester);
  final alta = repo ?? RepoAltaFalso();
  final fuenteCiudades = ciudades ?? CiudadesFalsas();
  final lista = RepoListaFalso([
    filaLista('vieja', calle: 'Grecia', numero: '3301'),
    filaLista('a', calle: 'Grecia', numero: '3305', metrosAlNorte: 12),
    filaLista('b', calle: 'Grecia', numero: '3309', metrosAlNorte: 4),
  ])..alta = alta;
  var secuencia = 0;
  final m = await montarMapaUbicaciones(
    tester,
    repo: lista,
    gps: gps,
    escala: escala,
    tamano: tamano,
    altaReal: true,
    ciudades: fuenteCiudades,
    otrosOverrides: [
      geocodificadorInversoProvider.overrideWithValue(
        geocodificador ?? GeocodificadorFalso(direccion655),
      ),
      ubicadorZonaProvider.overrideWithValue(ubicadorSinZonas()),
      esperaPuntoAltaProvider.overrideWithValue(const Duration(milliseconds: 20)),
      generadorIdUbicacionProvider.overrideWithValue(() => 'nueva-${++secuencia}'),
    ],
  );
  return Alta655(m, alta, fuenteCiudades);
}

Future<void> asentar655(WidgetTester tester, [int veces = 12]) => asentarLista(tester, veces);

/// Toca [boton] (lo trae a la vista antes) y deja correr los cuadros.
Future<void> tocar655(WidgetTester tester, Finder boton) async {
  await tester.ensureVisible(boton);
  await tester.pump();
  await tester.tap(boton);
  await asentar655(tester);
}

/// Toca el pin para sumar una casa: abre el alta en N·01.
Future<void> abrir655(WidgetTester tester) async {
  await tester.tap(botonNueva);
  await asentar655(tester);
}

Future<void> hastaQueHayAca655(WidgetTester tester) async {
  await abrir655(tester);
  await tocar655(tester, principal655);
}

AltaUbicacionState? estado655(WidgetTester tester) {
  final contenedor = contenedorDeLaPestana(tester);
  final modo = contenedor.read(mapaPrincipalProvider);
  return modo is ColocandoPin ? contenedor.read(altaUbicacionProvider(modo.alta)) : null;
}

String texto655(Finder boton) =>
    (find.descendant(of: boton, matching: find.byType(Text)).evaluate().first.widget as Text).data!;

bool habilitado655(WidgetTester tester, Finder boton) =>
    tester.widget<ButtonStyleButton>(boton).onPressed != null;

/// El alta que contesta con [candidatas] la primera vez y con el alta hecha después.
RepoAltaFalso conDuplicados655(List<CandidataDuplicado> candidatas) {
  var intento = 0;
  return RepoAltaFalso()
    ..comportamiento = (u) async => ++intento == 1
        ? Right(AltaConDuplicados(candidatas: candidatas))
        : Right(AltaRegistrada(ubicacion: u));
}

/// Un fallo en el primer intento y el alta hecha después.
RepoAltaFalso conFalloPrimero655([Failure falla = const FailureInesperado(causa: 'disco')]) {
  var intento = 0;
  return RepoAltaFalso()
    ..comportamiento = (u) async =>
        ++intento == 1 ? Left(falla) : Right(AltaRegistrada(ubicacion: u));
}

/// Los 11 artboards de la entrega 1.
enum Artboard655 {
  a01('41A·01 pin con GPS preciso'),
  a02('41A·02 sin GPS'),
  a03('41A·03 GPS impreciso'),
  a04('41A·04 N·02 ciudad, calle y número'),
  a04b('41A·04B elegí la ciudad'),
  a05('41A·05 pin movido con el número editado'),
  a06('41A·06 teclado abierto en N·02'),
  b01('41B·01 una candidata'),
  b02('41B·02 más de una'),
  b03('41B·03 crear igual con justificación'),
  b04('41B·04 misma dirección a menos de 100 m');

  const Artboard655(this.rotulo);
  final String rotulo;
}

/// Monta el alta y la lleva al artboard [a] en [tamano] con [escala].
Future<Alta655> llegarA655(
  WidgetTester tester,
  Artboard655 a, {
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  final gps = switch (a) {
    Artboard655.a02 => GpsFalso(
      const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado)),
    ),
    Artboard655.a03 => GpsFalso(Right(lecturaGps(85))),
    _ => null,
  };
  final repo = switch (a) {
    Artboard655.b01 ||
    Artboard655.b03 => conDuplicados655([candidata('vieja', calle: 'Grecia', numero: '3307')]),
    Artboard655.b02 => conDuplicados655([
      candidata('a', metros: 12, calle: 'Grecia', numero: '3307'),
      candidata('b', metros: 4, calle: 'Grecia', numero: '3309'),
    ]),
    Artboard655.b04 => conDuplicados655([
      candidata('vieja', metros: 26, calle: 'Grecia', numero: '3307', admiteConservarAmbos: false),
    ]),
    _ => null,
  };
  final t = await montar655(tester, gps: gps, repo: repo, tamano: tamano, escala: escala);
  await abrir655(tester);
  switch (a) {
    case Artboard655.a01 || Artboard655.a02 || Artboard655.a03:
      break;
    case Artboard655.a04:
      await tocar655(tester, principal655);
    case Artboard655.a04b:
      await tocar655(tester, principal655);
      await tocar655(tester, find.byKey(ClavesAltaMapa.ciudad));
    case Artboard655.a05:
      await tocar655(tester, principal655);
      await tester.enterText(find.byKey(ClavesAltaMapa.numero), '3307 B');
      await asentar655(tester);
      await tocar655(tester, secundario655);
      t.m.mapa.tocar(mataojo655);
      await asentar655(tester);
      await tocar655(tester, principal655);
    case Artboard655.a06:
      await tocar655(tester, principal655);
      tester.view.viewInsets = FakeViewPadding(bottom: tamano.height > 700 ? 300 : 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.showKeyboard(find.byKey(ClavesAltaMapa.numero));
      await asentar655(tester);
    case Artboard655.b01 || Artboard655.b02 || Artboard655.b04:
      await tocar655(tester, principal655);
      await tocar655(tester, principal655);
    case Artboard655.b03:
      await tocar655(tester, principal655);
      await tocar655(tester, principal655);
      await tocar655(tester, crearIgual655);
      await tester.enterText(justificacion655, 'Es la casa del fondo, con otra entrada.');
      await asentar655(tester);
  }
  return t;
}

/// La pantalla completa como PNG, solo con `QA_CAPTURAS`.
Future<void> capturar655(WidgetTester tester, String nombre) async {
  if (!conCapturas655) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/655_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado655(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    if (e.findAncestorWidgetOfExactType<InputDecorator>() != null) continue;
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// ¿El centro de [f] está dentro de lo que la hoja deja ver (su zona desplazable)?
bool enVistaDeLaHoja655(WidgetTester tester, Finder f) {
  final visible = tester.getRect(
    find.descendant(of: hojaAlta655, matching: find.byType(SingleChildScrollView)).first,
  );
  final c = tester.getRect(f.first).center;
  return visible.contains(c);
}

/// El color del píxel de la pantalla en [donde] (coordenadas lógicas, pixelRatio 1).
Future<Color> pixel655(WidgetTester tester, Offset donde) async {
  late Color color;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final datos = (await img.toByteData())!;
    final i = ((donde.dy.round() * img.width) + donde.dx.round()) * 4;
    color = Color.fromARGB(
      datos.getUint8(i + 3),
      datos.getUint8(i),
      datos.getUint8(i + 1),
      datos.getUint8(i + 2),
    );
  });
  return color;
}
