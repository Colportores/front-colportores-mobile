// Arnés del QA de «Detalle del cobro» y «Anular cobro» (vista 30 B, HU-COB-006, #168): lleva la
// pantalla a cada estado del canvas (30B-01 a 30B-08) y a los que el canvas no dibuja, con cualquier
// tamaño y escala de texto. Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a
// `.dart_tool/qa_capturas` (fuera de git).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agendar_visita_arnes.dart' show asentarAgendar;
import 'anular_cobro_arnes.dart';
import 'qa_vista23_408_arnes.dart' show cargarFuentes408, conCapturas408;

export 'qa_vista23_408_arnes.dart' show conCapturas408, usarFuentesReales408;

const chico168 = Size(360, 640);
const grande168 = Size(412, 915);

String sufijo168(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()}_x$e';

/// Cada estado al que se puede llegar. `c-30B-0N` son los artboards del canvas; el resto, los que el
/// canvas no dibuja.
enum Estado168 {
  c01Detalle('30B-01 Detalle del cobro'),
  c02Motivo('30B-02 Motivo obligatorio'),
  c03Otro('30B-03 Motivo Otro'),
  c04Confirmar('30B-04 Segunda confirmacion'),
  c05Anulado('30B-05 Anulado'),
  c06FueraDePlazo('30B-06 Pasaron las 72 h'),
  c07TicketValidado('30B-07 Ticket validado'),
  c08Error('30B-08 Error al anular'),
  otroVacio('Otro sin texto'),
  confirmarTarjeta('Confirmacion con tarjeta'),
  anulando('Anulando'),
  cargando('Cargando el cobro'),
  ausente('El cobro ya no esta'),
  errorDeLectura('Error de lectura'),
  ayer('Cobro de ayer');

  const Estado168(this.rotulo);
  final String rotulo;

  String get archivo => rotulo.replaceAll(' ', '_');
}

/// Lo que dejó el estado: el repositorio, por si hay que soltar una compuerta.
Future<AnulacionesEnMemoria> llegarA168(
  WidgetTester tester,
  Estado168 estado,
  Size tamano,
  double escala,
) async {
  await cargarFuentes408(tester);
  final tarjeta = estado == Estado168.c07TicketValidado || estado == Estado168.confirmarTarjeta;
  final repo = AnulacionesEnMemoria(
    cobros: estado == Estado168.ausente
        ? []
        : [
            detalleDeEjemplo(
              medio: tarjeta ? MedioCobranza.tarjeta : MedioCobranza.efectivo,
              fecha: estado == Estado168.ayer ? DateTime.utc(2026, 10, 22, 12, 30) : null,
            ),
          ],
  );
  if (estado == Estado168.c08Error) repo.fallas.add(const FailureCobroNoAnulado());
  if (estado == Estado168.anulando) repo.compuerta = Completer<void>();
  if (estado == Estado168.cargando) repo.compuertaDeLectura = Completer<void>();
  if (estado == Estado168.errorDeLectura) {
    repo.fallaDeLectura = const FailureCobroNoAnulado(causa: 'lectura');
  }
  await montarDetalleDelCobro(
    tester,
    repo: repo,
    ahora: estado == Estado168.c06FueraDePlazo ? DateTime.utc(2026, 10, 27) : null,
    ticketValidado: estado == Estado168.c07TicketValidado,
    escala: escala,
    tamano: tamano,
  );
  switch (estado) {
    case Estado168.c01Detalle ||
        Estado168.c06FueraDePlazo ||
        Estado168.c07TicketValidado ||
        Estado168.cargando ||
        Estado168.ausente ||
        Estado168.errorDeLectura ||
        Estado168.ayer:
      break;
    case Estado168.c02Motivo:
      await irAAnular(tester);
    case Estado168.c03Otro:
      await irAAnular(
        tester,
        m: MotivoDeAnulacion.otro,
        texto: 'El cliente pagó con transferencia',
      );
    case Estado168.otroVacio:
      await irAAnular(tester, m: MotivoDeAnulacion.otro);
    case Estado168.c04Confirmar || Estado168.confirmarTarjeta:
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);
    case Estado168.c05Anulado || Estado168.c08Error || Estado168.anulando:
      await irAAnular(tester, m: MotivoDeAnulacion.montoEquivocado);
      await tocar(tester, botonPrincipal);
      await tocar(tester, siAnular);
  }
  await asentarAgendar(tester, 3);
  return repo;
}

/// Suelta lo que dejó trabado el estado y deja correr los cuadros pendientes.
Future<void> liberar168(WidgetTester tester, AnulacionesEnMemoria repo) async {
  final compuerta = repo.compuerta;
  if (compuerta != null && !compuerta.isCompleted) compuerta.complete();
  final lectura = repo.compuertaDeLectura;
  if (lectura != null && !lectura.isCompleted) lectura.complete();
  await asentarAgendar(tester, 4);
}

/// La pantalla completa (incluidas las hojas) como PNG, solo con `QA_CAPTURAS`.
Future<void> capturar168(WidgetTester tester, String nombre) async {
  if (!conCapturas408) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/168_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado168(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    if (e.findAncestorWidgetOfExactType<InputDecorator>() != null) continue;
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}
