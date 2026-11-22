// Arnés del QA de la entrega para otro día y «Entregas pendientes» (HU-VEN-003, vista 27 grupo C,
// #435): lleva las tres pantallas reales (27C·01 «Entregar otro día», 27C·02/05/06/07 «Entregas
// pendientes» y 27C·03/04 «Marcar entregado») a cada estado al que una persona puede llegar, con las
// fuentes reales del proyecto y en los tamaños y la escala de texto del QA. Las capturas solo se sacan
// con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart'
    show ClavesAgendarVisita;
import 'package:colportores_mobile/features/inicio/presentation/widgets/barra_pestanas_inicio.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_pendiente.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/productos_de_la_entrega.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/entregar_otro_dia_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/entregas_pendientes_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/marcar_entregado_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/entrega_diferida_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'entrega_diferida_ui_falsos.dart';
import 'entrega_falsos.dart';
import 'qa_vista23_408_arnes.dart' show cargarFuentes408, conCapturas408;
import 'venta_falsos.dart';
import 'venta_ui_falsos.dart' show asentar, tocar;

export 'qa_vista23_408_arnes.dart' show cargarFuentes408, conCapturas408, usarFuentesReales408;

const chico435 = Size(360, 640);
const grande435 = Size(412, 915);

/// Cada estado de las tres pantallas al que se puede llegar.
enum Estado435 {
  otroDiaSinFecha('27C·01 sin fecha'),
  otroDiaConFecha('27C·01 con día y hora'),
  otroDiaHoja('27C·01 hoja Día y hora abierta'),
  otroDiaCargando('27C·01 cargando lo vendido'),
  otroDiaErrorDeLectura('27C·01 error al leer lo vendido'),
  otroDiaSinProductos('27C·01 venta sin productos'),
  otroDiaErrorAlGuardar('27C·01 error al guardar'),
  otroDiaGuardando('27C·01 guardando'),
  otroDiaPonerFecha('27C·02 Poner fecha'),
  pendientes('27C·02 lista'),
  pendientesVacia('27C·05 vacía'),
  pendientesCargando('27C·06 cargando'),
  pendientesError('27C·07 error al leer'),
  pendientesLarga('27C·02 con 40 entregas'),
  marcarTodo('27C·03 todo tildado'),
  marcarParcial('27C·04 con un libro destildado'),
  marcarParcialConFecha('27C·04 con nueva fecha'),
  marcarSinNada('27C·03 sin nada tildado'),
  marcarHoja('27C·04 hoja Día y hora abierta'),
  marcarCargando('27C·03 cargando'),
  marcarError('27C·03 error al leer'),
  marcarNadaPendiente('27C·03 nada pendiente'),
  marcarErrorAlGuardar('27C·03 error al guardar'),
  marcarGuardando('27C·03 guardando');

  const Estado435(this.rotulo);
  final String rotulo;
}

/// Lo que el montaje deja ver al test.
final class Montaje435 {
  Montaje435(this.entorno);
  final EntornoDeEntrega entorno;
}

Finder get cta435 => find.byKey(const Key('venta_cta'));
Finder get campo435 => find.byKey(const Key('entrega_campo_fecha'));

/// Elige el día [dia] (0 = hoy, 1 = mañana) en la hoja «Día y hora» y toca «Listo».
Future<void> elegirFecha435(WidgetTester tester, {int dia = 1}) async {
  await tocar(tester, campo435);
  await tester.ensureVisible(find.byKey(ClavesAgendarVisita.dia(dia)));
  await tester.tap(find.byKey(ClavesAgendarVisita.dia(dia)));
  await tester.pump();
  await tester.ensureVisible(find.byKey(ClavesAgendarVisita.hojaListo));
  await tester.tap(find.byKey(ClavesAgendarVisita.hojaListo));
  await asentar(tester);
}

Future<void> tocarCta435(WidgetTester tester) async {
  await tester.ensureVisible(cta435);
  await tester.pump();
  await tester.tap(cta435);
  await asentar(tester);
}

/// Una venta de [n] productos sueltos con nombre, para las listas largas.
({VentaGuardada guardada, ProductosDeLaEntrega productos}) ventaLarga435(int n, {String? nombre}) =>
    (
      guardada: VentaGuardada(
        venta: ventaDe('v-1', talonario: '0042', monto: 890000),
        items: [
          for (var i = 0; i < n; i++)
            itemDe('i-$i', 'v-1', productoId: 'p-$i', cantidad: 1, precio: 1000),
        ],
      ),
      productos: ProductosDeLaEntrega(
        nombres: {for (var i = 0; i < n; i++) 'p-$i': nombre ?? 'Libro número $i'},
      ),
    );

/// La lista de pendientes de los tests: una atrasada, una próxima y una sin fecha.
List<EntregaPendiente> lista435() => [
  pendienteDe('v-1', fecha: DateTime(2026, 10, 21, 16, 30), lineas: [lineaDe('e-1', 'p-hijos')]),
  pendienteDe(
    'v-2',
    fecha: DateTime(2026, 10, 31, 9),
    vinculo: 'ep-2',
    talonario: '0043',
    lineas: [lineaDe('e-2', 'p-salud'), lineaDe('e-3', 'p-hijos')],
  ),
  pendienteDe('v-3', vinculo: 'ep-3', talonario: '0044', lineas: [lineaDe('e-4', 'p-salud')]),
];

/// Lo pendiente de la venta v-1 en «Marcar entregado»: Salud y Hogar (e-1) y Nuestros Hijos (e-2).
EntregaPendiente pendienteDeMarcar435() => pendienteDe(
  'v-1',
  fecha: DateTime(2026, 10, 28, 16, 30),
  lineas: [lineaDe('e-1', 'p-salud'), lineaDe('e-2', 'p-hijos')],
);

/// [n] pendientes con nombres de persona y dirección largos (datos límite).
List<EntregaPendiente> listaLarga435(int n) => [
  for (var i = 0; i < n; i++)
    pendienteDe(
      'v-$i',
      fecha: i.isEven ? DateTime(2026, 10, 21 + (i % 8), 16, 30) : null,
      vinculo: 'ep-largo',
      talonario: '${1000 + i}',
      lineas: [lineaDe('e-$i-1', 'p-salud'), lineaDe('e-$i-2', 'p-hijos')],
    ),
];

const rotuloLargo435 = <String, RotuloDeEntrega>{
  ...rotulosDeLosTests,
  'ep-largo': (
    persona: 'María de los Ángeles Fernández de la Fuente Rodríguez',
    direccion: 'Avenida Doctor Luis Alberto de Herrera 1234 · Torre Norte · Apartamento 1203',
  ),
};

/// EntornoDeEntrega con lo que casi todo estado necesita.
EntornoDeEntrega entorno435({List<EntregaPendiente>? pendientes}) {
  final e = EntornoDeEntrega();
  e.entregas.emitirPendientes(pendientes ?? lista435());
  e.entregas.respuestaDeCumplir = cumplidaCon();
  e.entregas.respuestaDeDiferir = diferidaPara(DateTime(2026, 10, 29, 8, 30));
  return e;
}

Route<PestanaInicio> _rutaPendientes() => EntregasPendientesPage.ruta(colportorId: 'col-1');

/// Monta la pantalla de [estado] y la lleva hasta él.
Future<Montaje435> montar435(
  WidgetTester tester,
  Estado435 estado, {
  Size tamano = chico435,
  double escala = 1,
  EntornoDeEntrega? entorno,
}) async {
  await cargarFuentes408(tester);
  var e = entorno ?? entorno435();
  const nombre = 'María Fernández';
  var guardada = ventaConColeccion();
  switch (estado) {
    case Estado435.otroDiaSinProductos:
      guardada = VentaGuardada(
        venta: ventaDe('v-1', talonario: '0042'),
        items: const [],
      );
    case Estado435.otroDiaCargando:
      e.fuente.bloqueo = Completer<void>();
    case Estado435.otroDiaErrorDeLectura:
      e.fuente.fallas = 1;
    case Estado435.otroDiaGuardando:
      e.entregas.compuertaDeDiferida = Completer<void>();
    case Estado435.otroDiaErrorAlGuardar:
      e.entregas.fallasAlDiferir.add(const FailureEntregaNoGuardada());
    case Estado435.pendientesVacia:
      e.entregas.emitirPendientes(const []);
    case Estado435.pendientesLarga:
      e = entorno ?? entorno435(pendientes: listaLarga435(40));
    case Estado435.pendientesCargando:
      e = entorno ?? EntornoDeEntrega();
      e.entregas.respuestaDeCumplir = cumplidaCon();
    case Estado435.pendientesError:
      e.entregas.errorDePendientes = StateError('sin base');
    case Estado435.marcarCargando:
      e = entorno ?? EntornoDeEntrega();
    case Estado435.marcarTodo:
    case Estado435.marcarParcial:
    case Estado435.marcarParcialConFecha:
    case Estado435.marcarSinNada:
    case Estado435.marcarHoja:
    case Estado435.marcarErrorAlGuardar:
    case Estado435.marcarGuardando:
      e.entregas.emitirPendientes([pendienteDeMarcar435()]);
      if (estado == Estado435.marcarGuardando) e.entregas.compuertaDeDiferida = Completer<void>();
      if (estado == Estado435.marcarErrorAlGuardar) {
        e.entregas.fallasAlCumplir.add(const FailureEntregaNoGuardada());
      }
    case Estado435.marcarError:
      e.entregas.errorDePendientes = StateError('sin base');
    case Estado435.marcarNadaPendiente:
      e.entregas.emitirPendientes(const []);
    default:
      break;
  }
  switch (estado) {
    case Estado435.otroDiaSinFecha:
    case Estado435.otroDiaConFecha:
    case Estado435.otroDiaHoja:
    case Estado435.otroDiaCargando:
    case Estado435.otroDiaErrorDeLectura:
    case Estado435.otroDiaSinProductos:
    case Estado435.otroDiaErrorAlGuardar:
    case Estado435.otroDiaGuardando:
      await montarPantalla(
        tester,
        e,
        () => EntregarOtroDiaPage.ruta(guardada: guardada, nombreDelCliente: nombre),
        tamano: tamano,
        escala: escala,
      );
    case Estado435.otroDiaPonerFecha:
      await montarPantalla(
        tester,
        e,
        () => EntregarOtroDiaPage.rutaPonerFecha(
          colportorId: 'col-1',
          pendiente: pendienteDe(
            'v-3',
            vinculo: 'ep-3',
            talonario: '0044',
            lineas: [lineaDe('e-4', 'p-salud'), lineaDe('e-5', 'p-hijos')],
          ),
        ),
        tamano: tamano,
        escala: escala,
      );
    case Estado435.pendientes:
    case Estado435.pendientesVacia:
    case Estado435.pendientesCargando:
    case Estado435.pendientesError:
    case Estado435.pendientesLarga:
      await montarPantalla435(
        tester,
        e,
        _rutaPendientes,
        tamano: tamano,
        escala: escala,
        rotulos: estado == Estado435.pendientesLarga ? rotuloLargo435 : rotulosDeLosTests,
      );
    case Estado435.marcarTodo:
    case Estado435.marcarParcial:
    case Estado435.marcarParcialConFecha:
    case Estado435.marcarSinNada:
    case Estado435.marcarHoja:
    case Estado435.marcarCargando:
    case Estado435.marcarError:
    case Estado435.marcarNadaPendiente:
    case Estado435.marcarErrorAlGuardar:
    case Estado435.marcarGuardando:
      e.entregas.respuestaDeCumplir = cumplidaCon();
      await montarPantalla(
        tester,
        e,
        () => MarcarEntregadoPage.ruta(ventaId: 'v-1'),
        tamano: tamano,
        escala: escala,
      );
  }
  switch (estado) {
    case Estado435.otroDiaConFecha:
    case Estado435.otroDiaErrorAlGuardar:
    case Estado435.otroDiaGuardando:
      await elegirFecha435(tester);
    case Estado435.otroDiaHoja:
    case Estado435.marcarHoja:
      await tester.pump();
    default:
      break;
  }
  switch (estado) {
    case Estado435.marcarParcial:
    case Estado435.marcarParcialConFecha:
    case Estado435.marcarHoja:
      await tocar(tester, find.text('Nuestros Hijos × 1'));
    case Estado435.marcarSinNada:
      await tocar(tester, find.text('Salud y Hogar × 1'));
      await tocar(tester, find.text('Nuestros Hijos × 1'));
    default:
      break;
  }
  switch (estado) {
    case Estado435.marcarParcialConFecha:
      await elegirFecha435(tester);
    case Estado435.otroDiaHoja:
    case Estado435.marcarHoja:
      await tocar(tester, campo435);
    default:
      break;
  }
  switch (estado) {
    case Estado435.otroDiaErrorAlGuardar:
    case Estado435.otroDiaGuardando:
    case Estado435.marcarErrorAlGuardar:
    case Estado435.marcarGuardando:
      await tocarCta435(tester);
    default:
      break;
  }
  return Montaje435(e);
}

/// Si una compuerta quedó abierta, la suelta para que el test termine limpio.
Future<void> soltar435(WidgetTester tester, Montaje435 m) async {
  final c = m.entorno.entregas.compuertaDeDiferida;
  if (c != null && !c.isCompleted) c.complete();
  final b = m.entorno.fuente.bloqueo;
  if (b != null && !b.isCompleted) b.complete();
  await asentar(tester);
}

Future<void> capturar435(WidgetTester tester, String nombre) async {
  if (!conCapturas408) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/435_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado435(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

String nombreDeCaptura435(Estado435 e, Size t, double escala) =>
    '${e.name}_${t.width.toInt()}x${t.height.toInt()}_${escala.toStringAsFixed(0)}x';

/// Como `montarPantalla` del PR, pero con los rótulos que se le pasan (quién y dónde es cada vínculo).
Future<void> montarPantalla435<T>(
  WidgetTester tester,
  EntornoDeEntrega e,
  Route<T> Function() ruta, {
  required Map<String, RotuloDeEntrega> rotulos,
  required Size tamano,
  required double escala,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  e.ahora = ahoraDeLosTests;
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesDeEntregaDiferida(e, rotulos: rotulos),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('abrir_pantalla'),
                onPressed: () => Navigator.of(context).push<T>(ruta()),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await abrirPantalla(tester);
}
