// Arnés del QA de «Cobro en efectivo» (vista 28, HU-COB-001, #439): lleva la pantalla a cada estado del
// canvas (28·01 a 28·09) y a los que el canvas no dibuja, en cualquier tamaño y con cualquier escala de
// texto. Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas`
// (fuera de git).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agendar_visita_arnes.dart' show asentarAgendar;
import 'cobro_arnes.dart';
import 'qa_vista23_408_arnes.dart' show cargarFuentes408, conCapturas408, usarFuentesReales408;

export 'qa_vista23_408_arnes.dart' show conCapturas408, usarFuentesReales408;

const chico439 = Size(360, 640);
const grande439 = Size(412, 915);

String sufijo439(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()}_x$e';

/// Cada estado al que se puede llegar. `c0N` son los artboards del canvas; el resto, los que el canvas
/// no dibuja.
enum Estado439 {
  c01Formulario('28·01 Cobro en efectivo'),
  c02Vacio('28·02 Monto vacío'),
  c03Mayor('28·03 Monto mayor al saldo'),
  c04Hoja('28·04 Fecha de otro día'),
  c05Registrando('28·05 Registrando'),
  c06Parcial('28·06 Cobro parcial'),
  c07SaldoCero('28·07 Saldo en cero'),
  c08Error('28·08 Error al guardar'),
  cargando('Cargando la venta'),
  ausente('La venta ya no está'),
  errorLectura('Error de lectura'),
  sinSaldo('Venta sin saldo al abrir'),
  fechaRechazada('Fecha rechazada al guardar'),
  montoInvalido('Monto que no es un monto'),
  descartar('Aviso «¿Descartar lo que escribiste?»');

  const Estado439(this.rotulo);
  final String rotulo;
}

/// Lleva la pantalla a [estado]. Con [liberar] se suelta lo que dejó trabado ("Registrando…", la
/// lectura demorada) para que el test termine limpio.
Future<ArnesCobro> llegarA439(
  WidgetTester tester,
  Estado439 estado, {
  Size tamano = chico439,
  double escala = 1,
}) async {
  await cargarFuentes408(tester);
  Future<ArnesCobro> montar({CobranzasEnMemoria? repo, String ventaId = 'v-42'}) =>
      montarCobro(tester, repo: repo, ventaId: ventaId, escala: escala, tamano: tamano);

  switch (estado) {
    case Estado439.c01Formulario:
      final a = await montar();
      await _escribir(tester, '600');
      return a;
    case Estado439.c02Vacio:
      return montar();
    case Estado439.c03Mayor:
      final a = await montar();
      await _escribir(tester, r'$ 1.500');
      return a;
    case Estado439.c04Hoja:
      final a = await montar();
      await _escribir(tester, '600');
      await tocarCobro(tester, campoFecha);
      return a;
    case Estado439.c05Registrando:
      final repo = CobranzasEnMemoria()..compuerta = Completer<void>();
      final a = await montar(repo: repo);
      await _escribir(tester, '600');
      await tocarCobro(tester, botonRegistrar);
      return a;
    case Estado439.c06Parcial:
      final a = await montar();
      await _escribir(tester, '600');
      await tocarCobro(tester, botonRegistrar);
      return a;
    case Estado439.c07SaldoCero:
      final a = await montar();
      await _escribir(tester, '1200');
      await tocarCobro(tester, botonRegistrar);
      return a;
    case Estado439.c08Error:
      final repo = CobranzasEnMemoria()..fallas.add(const FailureCobroNoGuardado());
      final a = await montar(repo: repo);
      await _escribir(tester, '600');
      await tocarCobro(tester, botonRegistrar);
      return a;
    case Estado439.cargando:
      final repo = CobranzasEnMemoria()..compuertaDeLectura = Completer<void>();
      return montar(repo: repo);
    case Estado439.ausente:
      return montar(ventaId: 'no-existe');
    case Estado439.errorLectura:
      final repo = CobranzasEnMemoria()..fallaDeLectura = const FailureInesperado();
      return montar(repo: repo);
    case Estado439.sinSaldo:
      return montar(repo: CobranzasEnMemoria(cobradoAntes: 450000));
    case Estado439.fechaRechazada:
      final repo = CobranzasEnMemoria()..fallas.add(const FailureCobroFechaInvalida());
      final a = await montar(repo: repo);
      await _escribir(tester, '600');
      await tocarCobro(tester, botonRegistrar);
      return a;
    case Estado439.montoInvalido:
      final a = await montar();
      await _escribir(tester, '12abc');
      return a;
    case Estado439.descartar:
      final a = await montar();
      await _escribir(tester, '600');
      // Con letra grande el campo subió la lista: «✕» está arriba de todo.
      await tester.drag(
        find.descendant(of: pagina, matching: find.byType(Scrollable)).first,
        const Offset(0, 5000),
      );
      await asentarAgendar(tester, 4);
      await tocarCobro(tester, cerrarCobro);
      return a;
  }
}

/// Escribe el monto y deja terminar la animación del botón (de apagado a encendido tarda 200 ms:
/// medida a mitad de camino, la guía de contraste da un falso positivo).
Future<void> _escribir(WidgetTester tester, String texto) async {
  await escribirMonto(tester, texto);
  await tester.pump(const Duration(milliseconds: 400));
}

/// Suelta lo que dejó trabado el estado y deja correr los cuadros pendientes.
Future<void> liberar439(WidgetTester tester, ArnesCobro a) async {
  final compuerta = a.repo.compuerta;
  if (compuerta != null && !compuerta.isCompleted) compuerta.complete();
  final lectura = a.repo.compuertaDeLectura;
  if (lectura != null && !lectura.isCompleted) lectura.complete();
  await asentarAgendar(tester, 4);
}

/// La pantalla completa (incluidas las hojas) como PNG, solo con `QA_CAPTURAS`.
Future<void> capturar439(WidgetTester tester, String nombre) async {
  if (!conCapturas408) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/439_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado439(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    if (e.findAncestorWidgetOfExactType<InputDecorator>() != null) continue;
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// Las fuentes reales solo se apagan en el archivo de las guías de Flutter.
void sinFuentesReales439() => usarFuentesReales408 = false;
