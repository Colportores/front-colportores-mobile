// Arnés del QA de «Registrar venta» (vista 27, HU-VEN-001, #158 / PR #531): lleva la pantalla real a
// cada estado que una persona puede alcanzar (27A·01 a 27A·14 más los que el canvas no dibuja), con
// las fuentes reales del proyecto y los tamaños del QA. Las capturas solo se sacan con
// `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/` (nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/ciudad_consultable.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/precios_de_la_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/repositories/venta_repository.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/venta_registrada_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_vista23_408_arnes.dart' show cargarFuentes408, conCapturas408;
import 'venta_falsos.dart';
import 'venta_ui_falsos.dart';

export 'qa_vista23_408_arnes.dart' show conCapturas408, usarFuentesReales408;

const chico531 = Size(360, 640);
const grande531 = Size(412, 915);

Finder get cta531 => find.byKey(const Key('venta_cta'));
Finder campo531(String clave) =>
    find.descendant(of: find.byKey(Key(clave)), matching: find.byType(TextField));
bool habilitado531(WidgetTester tester) => tester.widget<FilledButton>(cta531).onPressed != null;

/// Cada pantalla o estado de la vista 27 a la que se puede llegar.
enum Estado531 {
  a01Seleccion('27A·01 Elegir la colección'),
  a02Armado('27A·02 Armado, falta un libro'),
  a03HojaLibro('27A·03 Hoja del libro'),
  a04Completa('27A·04 Colección completa'),
  a05Venta('27A·05 Venta con la colección'),
  a06CambiarLibro('27A·06 Cambiar un libro'),
  a07Revistas('27A·07 Sueltos revistas'),
  a08Misioneros('27A·08 Sueltos misioneros'),
  a10Campania('27A·10 Campaña terminada'),
  a11TalonarioRepetido('27A·11 Talonario repetido'),
  a12MontoSinMotivo('27A·12 Monto a mano sin motivo'),
  a12MontoConMotivo('27A·12 Monto a mano con motivo'),
  a13ErrorAlGuardar('27A·13 Error al guardar'),
  cargando('Cargando'),
  errorDeLectura('Error de lectura'),
  sinPrecios('Sin precios'),
  categoriaVacia('Categoría vacía'),
  confirmaSalida('Confirmación de salida'),
  guardando('Guardando'),
  a14Completa('27A·14 con entrega y cobro'),
  a14Sola('27A·14 solo confirmación');

  const Estado531(this.titulo);
  final String titulo;
}

/// Las colecciones de 2 libros con los dos libros elegidos, en la pantalla de la venta (27A·05).
Future<void> ventaConColeccion531(WidgetTester tester, {String talonario = '0042'}) async {
  await tocar(tester, find.text('Colección de 2 libros'));
  await tocar(tester, find.text(TextosVenta.armarLaColeccion));
  await elegirLibro531(tester, 1, 'Salud y Hogar');
  await elegirLibro531(tester, 2, 'Nuestros Hijos');
  await tocar(tester, find.text(TextosVenta.agregarALaVenta));
  if (talonario.isNotEmpty) {
    // La lista conserva dónde quedó al elegir la colección (a 2,0 el campo queda arriba, sin armar).
    await alPrincipio531(tester);
    await escribir(tester, campo531('venta_talonario'), talonario);
  }
}

/// Sube la lista hasta el principio (donde está el talonario).
Future<void> alPrincipio531(WidgetTester tester) async {
  await tester.drag(find.byType(ListView).first, const Offset(0, 5000));
  await asentar(tester);
}

/// Lleva la pantalla al estado [estado]; devuelve el entorno para que el test lo siga manejando.
Future<EntornoDeVenta> llegar531(
  WidgetTester tester,
  Estado531 estado, {
  Size tamano = chico531,
  double escala = 1,
  EntornoDeVenta? entorno,
}) async {
  await cargarFuentes408(tester);
  if (estado == Estado531.a14Completa || estado == Estado531.a14Sola) {
    await _montarRegistrada(tester, tamano, escala, conGrupos: estado == Estado531.a14Completa);
    return EntornoDeVenta();
  }
  final e =
      entorno ??
      switch (estado) {
        Estado531.a10Campania => EntornoDeVenta(
          precios: SinCampaniaVigente(
            terminada: CampaniaTerminada(
              nombre: 'Primavera 2026',
              terminoEl: DateTime(2026, 12, 15),
            ),
          ),
        ),
        Estado531.sinPrecios => EntornoDeVenta(precios: const SinCampaniaVigente()),
        _ => EntornoDeVenta(),
      };
  switch (estado) {
    case Estado531.cargando:
      e.fuente.bloqueo = Completer<void>();
    case Estado531.errorDeLectura:
      e.fuente.fallas = 1;
    default:
  }
  await montarNuevaVenta(tester, e, tamano: tamano, escala: escala);
  switch (estado) {
    case Estado531.a01Seleccion:
    case Estado531.cargando:
    case Estado531.errorDeLectura:
    case Estado531.sinPrecios:
    case Estado531.a14Completa:
    case Estado531.a14Sola:
      break;
    case Estado531.a10Campania:
      break;
    case Estado531.categoriaVacia:
      await tocar(tester, find.text('Misioneros'));
    case Estado531.a02Armado:
      await _armar(tester, libros: 0);
    case Estado531.a03HojaLibro:
      await _armar(tester, libros: 0);
      await tocar(tester, find.byKey(const Key('armar_libro_1')));
    case Estado531.a04Completa:
      await _armar(tester, libros: 2);
    case Estado531.a05Venta:
      await ventaConColeccion531(tester);
    case Estado531.a06CambiarLibro:
      await ventaConColeccion531(tester);
      await tocar(tester, find.text('Salud y Hogar · Nuestros Hijos'));
      await tocar(tester, find.byKey(const Key('armar_libro_1')));
    case Estado531.a07Revistas:
      await tocar(tester, find.text('Revistas'));
      await tocar(tester, find.byTooltip('Uno más de Vida Feliz'));
      await tocar(tester, find.byTooltip('Uno más de Vida Feliz'));
    case Estado531.a08Misioneros:
      await tocar(tester, find.text('Misioneros'));
      await tocar(tester, find.byTooltip('Uno más de El camino a Cristo'));
    case Estado531.a11TalonarioRepetido:
      e.ventas.talonario = VentaDelTalonario(ventaId: 'v-0', fecha: DateTime.utc(2026, 3, 12, 15));
      await ventaConColeccion531(tester);
    case Estado531.a12MontoSinMotivo:
      await ventaConColeccion531(tester);
      await tocar(tester, find.text('Cambiar el monto'));
      await escribir(tester, campo531('venta_monto'), '8500');
    case Estado531.a12MontoConMotivo:
      await ventaConColeccion531(tester);
      await tocar(tester, find.text('Cambiar el monto'));
      await escribir(tester, campo531('venta_monto'), '8500');
      await escribir(tester, campo531('venta_motivo'), 'descuento por pago en efectivo');
    case Estado531.a13ErrorAlGuardar:
      e.ventas.respuesta = const FailureVentaNoGuardada();
      await ventaConColeccion531(tester);
      await tocar(tester, cta531);
    case Estado531.confirmaSalida:
      await ventaConColeccion531(tester);
      await tester.binding.handlePopRoute();
      await asentar(tester);
    case Estado531.guardando:
      e.ventas.compuerta = Completer<void>().future;
      await ventaConColeccion531(tester);
      await tester.tap(cta531);
      await tester.pump();
  }
  return e;
}

Future<void> _armar(WidgetTester tester, {required int libros}) async {
  await tocar(tester, find.text('Colección de 2 libros'));
  await tocar(tester, find.text(TextosVenta.armarLaColeccion));
  if (libros >= 1) await elegirLibro531(tester, 1, 'Salud y Hogar');
  if (libros >= 2) await elegirLibro531(tester, 2, 'Nuestros Hijos');
}

/// Abre la hoja del libro [n], busca [nombre] (la lista es perezosa) y lo elige con «Listo».
Future<void> elegirLibro531(WidgetTester tester, int n, String nombre) async {
  await tocar(tester, find.byKey(Key('armar_libro_$n')));
  await escribir(tester, campo531('venta_hoja_libro_busqueda'), nombre.split(' ').first);
  await tocar(tester, find.text(nombre).last);
  await tocar(tester, find.text(TextosVenta.listo));
}

Future<void> _montarRegistrada(
  WidgetTester tester,
  Size tamano,
  double escala, {
  required bool conGrupos,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: temaClaro(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: VentaRegistradaPage(
        guardada: VentaGuardada(
          venta: ventaDe('v-1', talonario: '0042', monto: 890000),
          items: const [],
        ),
        nombreDelCliente: 'María Fernández',
        conEntrega: conGrupos,
        conCobro: conGrupos,
        alContinuar: (_) {},
        alTerminar: () {},
      ),
    ),
  );
  await asentar(tester);
}

/// Una captura PNG de toda la pantalla (con las hojas modales encima) en `.dart_tool/qa_capturas/`.
Future<void> capturar531(WidgetTester tester, String nombre) async {
  if (!conCapturas408) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/531_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado531(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    if (e.findAncestorWidgetOfExactType<InputDecorator>() != null) continue;
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// Si [f] está entero a la vista dentro de la lista que se desplaza (no tapado por el botón fijo ni
/// fuera del borde de la lista).
bool enVistaEnLaLista531(WidgetTester tester, Finder f) {
  if (f.evaluate().isEmpty) return false;
  final lista = tester.getRect(find.byType(ListView).first);
  final r = tester.getRect(f.first);
  return r.top >= lista.top - 0.5 && r.bottom <= lista.bottom + 0.5;
}

/// Baja la lista hasta el final (donde está el total).
Future<void> alFinal531(WidgetTester tester) async {
  await tester.drag(find.byType(ListView).first, const Offset(0, -5000));
  await asentar(tester);
}

String monto531(int centavos) => FormatoVenta.monto(centavos);
