// Arnés de los tests de QA de la vista 11 «Espacios» (HU-UBI-007, #211, PR #468): lleva la hoja a cada
// uno de sus estados (los tres artboards del canvas, los estados que el canvas no dibuja y los avisos
// de la baja), carga las fuentes reales y saca capturas a `.dart_tool/qa_capturas/211_*.png`
// (gitignored: nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/hoja_espacios_arnes.dart';
import 'espacios_falsos.dart';

export '../widget/mapa/hoja_espacios_arnes.dart';
export 'espacios_falsos.dart';

/// Los dos tamaños de la matriz de QA (móvil chico y grande).
const telefonoChico211 = Size(360, 640);
const telefonoGrande211 = Size(412, 915);

/// ¿Se cargan las fuentes reales? Los tests de las guías de contraste las apagan (con letra real el
/// `textContrastGuideline` da falsos negativos).
bool usarFuentesReales211 = true;
var _fuentesCargadas = false;

Future<void> cargarFuentes211(WidgetTester tester) async {
  if (_fuentesCargadas || !usarFuentesReales211) return;
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

/// Una captura PNG de todo lo que se ve (incluidas las hojas y los diálogos) en
/// `.dart_tool/qa_capturas/211_<nombre>.png`. Solo si se pasa `--dart-define=QA_CAPTURAS=true`.
Future<void> capturar211(WidgetTester tester, String nombre) async {
  if (!const bool.fromEnvironment('QA_CAPTURAS')) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & (vista.size));
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/211_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Los seis deptos del canvas 11·01 («Mataojo 2044 · 6 deptos»): dos en el piso 1, dos en el 2, uno
/// «PB-A» sin piso y uno sin número (el de la casa que se unió).
List<Espacio> deptosDelCanvas() => [
  espacioDe('e-101', '101', piso: '1', orden: 1),
  espacioDe('e-102', '102', piso: '1', orden: 2),
  espacioDe('e-201', '201', piso: '2', orden: 3),
  espacioDe('e-202', '202', piso: '2', orden: 4),
  espacioDe('e-pba', 'PB-A', orden: 5),
  espacioDe('e-sn', null, orden: 6),
];

/// Cada estado al que la hoja se puede llegar.
enum EstadoV11 {
  lista('11·01 lista'),
  vacio('vacío'),
  cargando('cargando'),
  errorLista('error de lectura'),
  casa('casa (sin deptos)'),
  alta('11·02 alta'),
  altaSinNumero('alta sin número'),
  repetido('11·03 repetido'),
  fallaGuardado('falla al guardar'),
  edicion('edición'),
  agregadoOtro('alta tras «Agregar y cargar otro»'),
  preguntaBaja('baja sin personas'),
  preguntaBajaSinNumero('baja de un depto sin número'),
  avisoPersonas('baja con personas'),
  bajaBloqueada('baja bloqueada');

  const EstadoV11(this.rotulo);

  final String rotulo;
}

/// Monta la hoja a [tamano] y [escala] y la lleva a [estado].
Future<MontajeHoja> llegarA(
  WidgetTester tester,
  EstadoV11 estado, {
  Size tamano = telefonoGrande211,
  double escala = 1,
}) async {
  await cargarFuentes211(tester);
  Future<MontajeHoja> montar({
    Ubicacion? ubicacion,
    List<Espacio>? espacios,
    Map<String, int>? personas,
    bool abrir = true,
  }) => montarHoja(
    tester,
    ubicacion: ubicacion,
    espacios: espacios ?? deptosDelCanvas(),
    personas: personas,
    tamano: tamano,
    escala: escala,
    abrir: abrir,
  );
  switch (estado) {
    case EstadoV11.lista:
      return montar();
    case EstadoV11.vacio:
      return montar(espacios: const []);
    case EstadoV11.cargando:
      final m = await montar(abrir: false);
      m.repo.esperaAlListar = Completer<void>();
      await abrirLaHoja(tester);
      return m;
    case EstadoV11.errorLista:
      final m = await montar(abrir: false);
      m.repo.fallaAlListar = const FailureInesperado(causa: 'x');
      await abrirLaHoja(tester);
      return m;
    case EstadoV11.casa:
      return montar(
        ubicacion: edificioMataojo(tipo: TipoUbicacion.casa),
        espacios: const [],
      );
    case EstadoV11.alta:
      final m = await montar();
      await abrirAltaDepto(tester);
      return m;
    case EstadoV11.altaSinNumero:
      final m = await montar();
      await abrirAltaDepto(tester);
      await tester.tap(botonAgregar);
      await asentarHoja(tester);
      return m;
    case EstadoV11.repetido:
      final m = await montar();
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, '102');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);
      return m;
    case EstadoV11.fallaGuardado:
      final m = await montar();
      await abrirAltaDepto(tester);
      m.repo.fallas.add(const FailureInesperado(causa: 'disco'));
      await escribir(tester, campoNumero, '301');
      await tester.tap(botonAgregar);
      await asentarHoja(tester);
      return m;
    case EstadoV11.edicion:
      final m = await montar();
      await abrirEdicionDepto(tester, 'e-101');
      return m;
    case EstadoV11.agregadoOtro:
      final m = await montar();
      await abrirAltaDepto(tester);
      await escribir(tester, campoNumero, '301');
      await tester.tap(botonAgregarYCargarOtro);
      await asentarHoja(tester);
      return m;
    case EstadoV11.preguntaBajaSinNumero:
      final m = await montar();
      tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!.jumpTo(5000);
      await asentarHoja(tester);
      await abrirEdicionDepto(tester, 'e-sn');
      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);
      return m;
    case EstadoV11.preguntaBaja:
      final m = await montar();
      await abrirEdicionDepto(tester, 'e-101');
      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);
      return m;
    case EstadoV11.avisoPersonas:
      final m = await montar(personas: {'e-101': 3});
      await abrirEdicionDepto(tester, 'e-101');
      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);
      return m;
    case EstadoV11.bajaBloqueada:
      final m = await montar(
        espacios: [espacioDe('e-1', '101', piso: '1')],
        personas: {'e-1': 2},
      );
      await abrirEdicionDepto(tester, 'e-1');
      await tester.tap(botonDarDeBaja);
      await asentarHoja(tester);
      return m;
  }
}

/// Ningún texto visible se sale de la pantalla por los costados.
void expectSinTextoFueraDeLosCostados211(WidgetTester tester, Size tamano) {
  for (final e in find.byType(RichText).evaluate()) {
    final render = e.renderObject;
    if (render is! RenderBox || !render.attached || !render.hasSize) continue;
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
