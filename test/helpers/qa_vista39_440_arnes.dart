// Arnés del QA de «$ Cobrar» desde la casa (vista 39, C·08 «¿Qué venta?», #440): lleva la hoja a cada
// estado (los del canvas y los que el canvas no dibuja), en cualquier tamaño y con cualquier escala de
// texto. Las capturas solo con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas`
// (fuera de git).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/venta_con_saldo.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/widgets/hoja_que_venta.dart'
    show ClavesQueVenta;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agendar_visita_arnes.dart' show asentarAgendar;
import 'cobrar_desde_la_casa_arnes.dart';
import 'qa_vista23_408_arnes.dart' show cargarFuentes408, conCapturas408, usarFuentesReales408;

export 'qa_vista23_408_arnes.dart' show conCapturas408, usarFuentesReales408;

const chico440 = Size(360, 640);
const grande440 = Size(412, 915);

String sufijo440(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()}_x$e';

/// Cada estado al que se puede llegar. `c08…` es el artboard del canvas; el resto, lo que el canvas no
/// dibuja (los textos «A confirmar» del PR).
enum Estado440 {
  c08Lista('C·08 Cobrar: ¿qué venta?'),
  c08SegundaElegida('C·08 con la segunda venta elegida'),
  c08Lector('C·08 con el lector de pantalla'),
  c08Muchas('C·08 con 14 ventas y textos largos'),
  c08SinNombre('C·08 sin nombre (la persona ya no vive ahí)'),
  c08SinDescripcion('C·08 con una venta sin descripción'),
  cargando('Cargando las ventas'),
  sinSaldo('Sin ventas con saldo'),
  sinSaldoSinNombre('Sin ventas con saldo y sin nombre'),
  errorLectura('Error al leer las ventas'),
  errorLecturaTrasReintento('Error al leer, dos veces');

  const Estado440(this.rotulo);
  final String rotulo;
}

/// 14 ventas, cada una con una descripción larga como las que arma la base con varios productos.
List<VentaConSaldo> ventasMuchas440() => [
  for (var i = 0; i < 14; i++)
    VentaConSaldo(
      ventaId: 'v-m$i',
      numeroTalonario: (1000 + i).toString().padLeft(6, '0'),
      fecha: DateTime.utc(2026, 9, 1 + i, 15),
      montoTotalCentavos: 1234567 + i * 1000,
      cobradoCentavos: i * 100,
      descripcion: i.isEven
          ? 'El Conflicto de los Siglos × 3 · Colección de 12 libros · Vida Feliz × 2 · 4 productos'
          : 'Libro de nombre larguísimo que no entra en una sola línea de la hoja × 12',
    ),
];

/// Lo que dejó montar un estado: el resultado de la hoja y el repositorio que controla la lectura.
typedef Montaje440 = ({ResultadoQueVenta resultado, CobranzasQueLeen repo});

/// Lleva la hoja a [estado].
Future<Montaje440> llegarA440(
  WidgetTester tester,
  Estado440 estado, {
  Size tamano = chico440,
  double escala = 1,
}) async {
  await cargarFuentes408(tester);
  Future<Montaje440> montar(
    CobranzasQueLeen repo, {
    String? nombre = 'Pedro',
    bool lector = false,
  }) async {
    final r = await montarQueVenta(
      tester,
      repo: repo,
      nombre: nombre,
      escala: escala,
      tamano: tamano,
      lector: lector,
    );
    return (resultado: r, repo: repo);
  }

  switch (estado) {
    case Estado440.c08Lista:
      return montar(cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]));
    case Estado440.c08SegundaElegida:
      final m = await montar(cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]));
      await tocarFilaQueVenta440(tester, 'v-45');
      return m;
    case Estado440.c08Lector:
      return montar(cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]), lector: true);
    case Estado440.c08Muchas:
      return montar(cobranzasConVentas(ventasMuchas440()));
    case Estado440.c08SinNombre:
      return montar(cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()]), nombre: null);
    case Estado440.c08SinDescripcion:
      return montar(
        cobranzasConVentas(const [])
          ..fija = [
            ventaDelCanvas38(),
            VentaConSaldo(
              ventaId: 'v-77',
              numeroTalonario: '0077',
              fecha: DateTime.utc(2026, 10, 22, 15),
              montoTotalCentavos: 50000,
              cobradoCentavos: 10000,
            ),
          ],
      );
    case Estado440.cargando:
      final repo = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()])
        ..compuerta = Completer<void>();
      return montar(repo);
    case Estado440.sinSaldo:
      return montar(cobranzasConVentas(const []));
    case Estado440.sinSaldoSinNombre:
      return montar(cobranzasConVentas(const []), nombre: null);
    case Estado440.errorLectura:
      final repo = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()])
        ..fallas.add(const FailureInesperado());
      return montar(repo);
    case Estado440.errorLecturaTrasReintento:
      final repo = cobranzasConVentas([ventaDelCanvas38(), ventaDelCanvas45()])
        ..fallas.addAll([const FailureInesperado(), const FailureInesperado()]);
      final m = await montar(repo);
      await tocarQueVenta(tester, find.byKey(const Key('que_venta_reintentar')));
      return m;
  }
}

/// Lleva la fila de [ventaId] a la vista (la lista es perezosa: con letra grande la segunda ni se
/// construye hasta que se desplaza) y la toca.
Future<void> tocarFilaQueVenta440(WidgetTester tester, String ventaId) async {
  final fila = find.byKey(ClavesQueVenta.fila(ventaId));
  final lista = find.byKey(ClavesQueVenta.lista);
  for (var i = 0; i < 120 && fila.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(lista, const Offset(0, -300));
    await tester.pump();
  }
  await tester.pump();
  await tester.tap(fila);
  await asentarAgendar(tester);
}

/// Suelta lo que dejó trabado el estado y deja correr los cuadros pendientes.
Future<void> liberar440(WidgetTester tester, Montaje440 m) async {
  final compuerta = m.repo.compuerta;
  if (compuerta != null && !compuerta.isCompleted) compuerta.complete();
  await asentarAgendar(tester, 4);
}

/// La pantalla completa (incluidas las hojas) como PNG, solo con `QA_CAPTURAS`.
Future<void> capturar440(WidgetTester tester, String nombre) async {
  if (!conCapturas408) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/440_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado440(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// Las fuentes reales solo se apagan en el archivo de las guías de Flutter.
void sinFuentesReales440() => usarFuentesReales408 = false;
