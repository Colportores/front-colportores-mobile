// Arnés del QA de «Entregar ahora» (HU-VEN-002, vista 27 grupo B, #159): lleva la pantalla real a cada
// estado que una persona puede alcanzar (los de los artboards 27B·01, 27B·03 y 27B·04 y los que el
// canvas no dibuja), en los tamaños y con el texto del QA, con las fuentes reales del proyecto. Las
// capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/piezas_entrega.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'entrega_falsos.dart';
import 'qa_vista23_408_arnes.dart' show cargarFuentes408, conCapturas408;
import 'venta_falsos.dart';
import 'venta_ui_falsos.dart' show asentar;

export 'qa_vista23_408_arnes.dart' show cargarFuentes408, conCapturas408, usarFuentesReales408;

const chico159 = Size(360, 640);
const grande159 = Size(412, 915);

/// Cada estado de «Entregar ahora» al que se puede llegar.
enum Estado159 {
  formulario('27B·01 todo tildado'),
  parcial('27B·01 con un libro destildado'),
  sinNada('27B·01 sin nada tildado'),
  cargando('cargando lo vendido'),
  errorDeLectura('error al leer lo vendido'),
  sinProductos('venta sin productos'),
  errorAlGuardar('error al guardar'),
  guardando('guardando'),
  completa('27B·03 venta completa'),
  conSaldo('27B·04 entregada con saldo'),
  conSaldoConDestinos('27B·04 con Cobrar y Agendar'),
  parcialResultado('resultado de una entrega parcial'),
  reentrada('reentrada: ya estaba entregada');

  const Estado159(this.rotulo);
  final String rotulo;
}

/// Lo que el montaje deja ver al test.
final class Montaje159 {
  Montaje159(this.entorno, this.salida);
  final EntornoDeEntrega entorno;
  final SalidaDeEntrega salida;
}

Finder get filas159 => find.byType(FilaDeEntrega);
Finder get cta159 => find.byKey(const Key('venta_cta'));

/// Toca la fila [i] de «Qué entregás».
Future<void> tocarFila159(WidgetTester tester, int i) async {
  await tester.ensureVisible(filas159.at(i));
  await tester.pump();
  await tester.tap(filas159.at(i));
  await asentar(tester);
}

/// Destilda todas las filas, bajando por la lista (es perezosa) y volviendo arriba al final.
Future<void> destildarTodo159(WidgetTester tester) async {
  final lista = find.byType(Scrollable).first;
  for (var vuelta = 0; vuelta < 12; vuelta++) {
    while (find.byIcon(Icons.check).evaluate().isNotEmpty) {
      final fila = find.ancestor(of: find.byIcon(Icons.check).first, matching: filas159);
      await tester.ensureVisible(fila.first);
      await tester.pump();
      await tester.tap(fila.first);
      await asentar(tester);
    }
    await tester.drag(lista, const Offset(0, -250));
    await asentar(tester);
  }
  await tester.drag(lista, const Offset(0, 8000));
  await asentar(tester);
}

/// Toca la fila que dice [texto].
Future<void> tocarTexto159(WidgetTester tester, String texto) async {
  await tester.ensureVisible(find.text(texto));
  await tester.pump();
  await tester.tap(find.text(texto));
  await asentar(tester);
}

Future<void> tocarCta159(WidgetTester tester) async {
  await tester.ensureVisible(cta159);
  await tester.pump();
  await tester.tap(cta159);
  await asentar(tester);
}

/// Monta «Entregar ahora» y lo lleva a [estado].
Future<Montaje159> montar159(
  WidgetTester tester,
  Estado159 estado, {
  Size tamano = chico159,
  double escala = 1,
  VentaGuardada? venta,
  EntornoDeEntrega? entorno,
}) async {
  await cargarFuentes408(tester);
  final e = entorno ?? EntornoDeEntrega();
  var guardada =
      venta ??
      switch (estado) {
        Estado159.completa => ventaDeUnaRevista(cantidad: 2),
        Estado159.sinProductos => VentaGuardada(
          venta: ventaDe('v-1', talonario: '0042'),
          items: const [],
        ),
        _ => ventaConColeccion(conRevista: true),
      };
  switch (estado) {
    case Estado159.cargando:
      e.fuente.bloqueo = Completer<void>();
    case Estado159.errorDeLectura:
      e.fuente.fallas = 1;
    case Estado159.errorAlGuardar:
      e.entregas.fallas.add(const FailureEntregaNoGuardada());
    case Estado159.guardando:
      e.entregas.compuerta = Completer<void>();
    case Estado159.reentrada:
      e.entregas.guardadas['v-1'] = [
        entregaDe('e-a', 'p-camino'),
        entregaDe('e-b', 'p-salud'),
        entregaDe('e-c', 'p-hijos', pendiente: true),
      ];
    default:
      break;
  }
  if (estado == Estado159.completa) {
    guardada = VentaGuardada(
      venta: ventaDe('v-1', talonario: '0042', monto: 0),
      items: guardada.items,
    );
  }
  final conDestinos = estado == Estado159.conSaldoConDestinos;
  final salida = await montarEntrega(
    tester,
    e,
    guardada,
    escala: escala,
    tamano: tamano,
    conCobro: conDestinos,
    conAgendar: conDestinos,
  );
  switch (estado) {
    case Estado159.parcial:
    case Estado159.parcialResultado:
      await tocarTexto159(tester, 'Nuestros Hijos × 1');
    case Estado159.sinNada:
      await destildarTodo159(tester);
    default:
      break;
  }
  switch (estado) {
    case Estado159.errorAlGuardar:
    case Estado159.guardando:
    case Estado159.completa:
    case Estado159.conSaldo:
    case Estado159.conSaldoConDestinos:
    case Estado159.parcialResultado:
      await tocarCta159(tester);
    default:
      break;
  }
  return Montaje159(e, salida);
}

/// Si la compuerta del guardado quedó abierta, la suelta para que el test termine limpio.
Future<void> soltar159(WidgetTester tester, Montaje159 m) async {
  final c = m.entorno.entregas.compuerta;
  if (c != null && !c.isCompleted) c.complete();
  final b = m.entorno.fuente.bloqueo;
  if (b != null && !b.isCompleted) b.complete();
  await asentar(tester);
}

/// El rectángulo [f] cabe entero en la pantalla.
bool enPantalla159(WidgetTester tester, Finder f) {
  final r = tester.getRect(f.first);
  final v = tester.view.physicalSize / tester.view.devicePixelRatio;
  return r.top >= -0.5 && r.left >= -0.5 && r.bottom <= v.height + 0.5 && r.right <= v.width + 0.5;
}

Future<void> capturar159(WidgetTester tester, String nombre) async {
  if (!conCapturas408) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/159_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado159(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

String nombreDeCaptura159(Estado159 e, Size t, double escala) =>
    '${e.name}_${t.width.toInt()}x${t.height.toInt()}_${escala.toStringAsFixed(0)}x';
