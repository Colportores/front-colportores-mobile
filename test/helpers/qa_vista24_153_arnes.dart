// Arnés de la QA de #153 (HU-NOT-001, vista 24 grupo A): lleva la app, o la pantalla suelta, a cada
// artboard del canvas (24A·01 a 24A·06) y a los estados de la HU que el canvas no dibuja, en el tamaño
// y con la escala de texto que pida el test, con las fuentes reales del proyecto.
//
// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`
// (ignorado por git: nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/permiso_notificaciones_repository.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/notificaciones_page.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'notificaciones_arnes.dart';

const conCapturas = bool.fromEnvironment('QA_CAPTURAS');

/// Los teléfonos de la matriz de la QA: el chico y el grande.
const tamanos = [Size(360, 640), Size(412, 915)];
const escalas = [1.0, 2.0];

/// Cada artboard del grupo A del canvas 24 y los estados de la HU que el canvas no dibuja.
enum Estado24 {
  a01('24A·01 pedido del permiso'),
  a02('24A·02 diálogo del sistema abierto (botones esperando)'),
  a02Fallo('24A·02 el sistema no mostró el diálogo (falla a mitad)'),
  a03('24A·03 dijo que no: aviso sutil en Hoy'),
  a04('24A·04 activadas (éxito)'),
  a05('24A·05 activadas sin conexión'),
  a06('24A·06 bloqueadas en el teléfono'),
  a06AjustesNoAbren('24A·06 los ajustes no se abren'),
  activadas('Configuración › Notificaciones activadas'),
  sinPedir('Configuración › Notificaciones apagadas con «Activar»'),
  cargando('Configuración › Notificaciones cargando'),
  errorAlLeer('Configuración › Notificaciones error al leer'),
  fallaAlActivar('Configuración › Notificaciones falla al activar');

  const Estado24(this.rotulo);

  final String rotulo;
}

bool _fuentesCargadas = false;

/// `false` solo para la guía de contraste de Flutter: lee los colores del texto de la captura y con las
/// fuentes reales (trazos de 1 px, suavizados) da falsos negativos.
bool usarFuentesReales = true;

/// Sin las fuentes del proyecto `flutter_test` pinta cajas (Ahem) y las medidas no son las reales.
Future<void> cargarFuentes(WidgetTester tester) async {
  if (_fuentesCargadas || !usarFuentesReales) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    final raiz = Platform.environment['FLUTTER_ROOT'];
    final iconos = File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (raiz != null && iconos.existsSync()) {
      final bytes = iconos.readAsBytesSync();
      final cargador = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
  });
  _fuentesCargadas = true;
}

/// Lo que el test necesita del estado alcanzado.
final class Alcanzado {
  Alcanzado(this.telefono, this.dialogo);

  final Telefono telefono;

  /// El diálogo del sistema abierto (a02), para contestarlo.
  final Completer<void>? dialogo;
}

/// Lleva la app (o la pantalla) a [e] con el tamaño y la escala dados.
Future<Alcanzado> llegarA(
  WidgetTester tester,
  Estado24 e, {
  Size tam = const Size(360, 640),
  double escala = 1,
}) async {
  fijarTamano(tester, tamano: tam, texto: escala);
  await cargarFuentes(tester);
  Completer<void>? dialogo;
  final t = Telefono();
  switch (e) {
    case Estado24.a01:
      await abrirApp(tester, t);
    case Estado24.a02:
      dialogo = t.sistema.dialogoAbierto = Completer<void>();
      await abrirApp(tester, t);
      await tocar(tester, pedidoActivar);
      await tester.pump();
    case Estado24.a02Fallo:
      t.sistema.fallaAlPedir = true;
      await abrirApp(tester, t);
      await tocar(tester, pedidoActivar);
      await tester.pumpAndSettle();
    case Estado24.a03:
      t.recuerdo.pedido = PedidoNotificaciones.ahoraNo;
      await abrirApp(tester, t);
    case Estado24.a04:
      await abrirApp(tester, t);
      await tocar(tester, pedidoActivar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    case Estado24.a05:
      t.conexion.tipo = TipoConexion.sinConexion;
      await abrirApp(tester, t);
      await tocar(tester, pedidoActivar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    case Estado24.a06:
      t.recuerdo.pedido = PedidoNotificaciones.sistema;
      await abrirPantalla(tester, t, const NotificacionesPage());
    case Estado24.a06AjustesNoAbren:
      t.recuerdo.pedido = PedidoNotificaciones.sistema;
      t.sistema.puedeAbrirAjustes = false;
      await abrirPantalla(tester, t, const NotificacionesPage());
      await tocar(tester, find.byKey(const Key('notificaciones_abrir_ajustes')));
      await tester.pumpAndSettle();
    case Estado24.activadas:
      t.sistema.estado = EstadoSistemaNotificaciones.activadas;
      await abrirPantalla(tester, t, const NotificacionesPage());
    case Estado24.sinPedir:
      t.recuerdo.pedido = PedidoNotificaciones.ahoraNo;
      await abrirPantalla(tester, t, const NotificacionesPage());
    case Estado24.cargando:
      t.sistema.lecturaDemorada = Completer<void>();
      await abrirPantallaSinEsperar(tester, t, const NotificacionesPage());
    case Estado24.errorAlLeer:
      t.sistema.fallaAlLeer = true;
      await abrirPantalla(tester, t, const NotificacionesPage());
    case Estado24.fallaAlActivar:
      t.recuerdo.pedido = PedidoNotificaciones.ahoraNo;
      t.sistema.fallaAlPedir = true;
      await abrirPantalla(tester, t, const NotificacionesPage());
      await tocar(tester, find.byKey(const Key('notificaciones_activar')));
      await tester.pumpAndSettle();
  }
  return Alcanzado(t, dialogo);
}

/// Como una persona: desplaza hasta el botón y lo toca.
Future<void> tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

/// Cierra la app y deja correr lo que quede pendiente (timers del toast).
Future<void> cerrar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 10));
}

/// Ningún texto se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// El centro de [f] está dentro de la pantalla visible (se puede tocar sin desplazar más).
void dentroDeLaPantalla(WidgetTester tester, Finder f, Size tam) {
  final r = tester.getRect(f.first);
  expect(r.top, greaterThanOrEqualTo(-0.5), reason: 'se sale por arriba');
  expect(r.bottom, lessThanOrEqualTo(tam.height + 0.5), reason: 'se sale por abajo');
  expect(r.left, greaterThanOrEqualTo(-0.5), reason: 'se sale por la izquierda');
  expect(r.right, lessThanOrEqualTo(tam.width + 0.5), reason: 'se sale por la derecha');
}

/// Guarda la pantalla entera (incluye hojas y SnackBar) en `.dart_tool/qa_capturas/`.
Future<void> capturar(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/qa153_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Las palabras que no entran enteras en el ancho de su renglón (se parten a la mitad). Ignora los
/// textos de un campo de edición.
List<String> palabrasPartidas(WidgetTester tester) {
  final partidas = <String>[];
  for (final e in find.byType(RichText).evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    final raiz = p.text;
    if (raiz is! TextSpan) continue;
    final ancho = p.size.width;
    for (final palabra in raiz.toPlainText().split(RegExp(r'\s+'))) {
      if (palabra.isEmpty) continue;
      final medida = TextPainter(
        text: TextSpan(text: palabra, style: raiz.style),
        textDirection: TextDirection.ltr,
        textScaler: p.textScaler,
      )..layout();
      if (medida.width > ancho + 0.5) partidas.add('«$palabra» (${medida.width} > $ancho)');
    }
  }
  return partidas;
}
