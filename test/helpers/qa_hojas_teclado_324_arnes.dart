// Arnés del QA de #324 / PR #342 (hojas 03 «Alta de ubicación» y 07 «Modificar ubicación» con el teclado
// abierto): lo común a los dos arneses de las vistas (`alta_ubicacion_qa_317_arnes.dart` y
// `modificar_ubicacion_qa_307_arnes.dart`, que se pisan los nombres) más las medidas de la QA: la ventana que
// el teclado deja libre, cuánto de un control se ve, los anuncios al lector de pantalla, quién tiene el
// foco y las capturas.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'alta_ubicacion_falsos.dart';
import 'alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import 'mapa_base_falso.dart';
import 'modificar_ubicacion_falsos.dart';

/// Un teléfono del QA: nombre, tamaño en dp y alto del teclado abierto.
typedef Telefono = ({String nombre, Size tamano, double teclado});

const telefonos = <Telefono>[
  (nombre: '360×640', tamano: Size(360, 640), teclado: 300.0),
  (nombre: '412×915', tamano: Size(412, 915), teclado: 340.0),
];

/// El más chico que probamos: «Cerrar» queda con 45 de 48 dp (pendiente P1 del implementador).
const telefonoMinimo = (nombre: '320×568', tamano: Size(320, 568), teclado: 300.0);

/// «1×», «1,3×»…
String veces(double escala) => escala == escala.roundToDouble()
    ? '${escala.round()}×'
    : '${escala.toString().replaceAll('.', ',')}×';

/// Lo que el teclado deja libre de la pantalla.
Rect ventanaLibre(Size tamano, double teclado) =>
    Rect.fromLTWH(0, 0, tamano.width, tamano.height - teclado);

/// Cuánto del alto de [r] cae dentro de [ventana].
double alturaVisible(Rect r, Rect ventana) =>
    math.max(0, math.min(r.bottom, ventana.bottom) - math.max(r.top, ventana.top));

/// Cuánto del alto de [r] queda fuera de [area].
double corteVertical(Rect r, Rect area) => r.height - alturaVisible(r, area);

/// La raíz de las capturas de la edición montada con [abrirEdicionQa].
final raizQa = GlobalKey();

/// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true`.
const conCapturas = bool.fromEnvironment('QA_CAPTURAS');

/// Una captura PNG de la pantalla en `.dart_tool/qa_capturas/` (gitignored, fuera del commit). Cada
/// arnés (alta, edición) arma su propia [raiz] de captura.
Future<void> capturarEn(WidgetTester tester, GlobalKey raiz, String nombre) async {
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/342_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Las fuentes del proyecto y los íconos de Material: con las de prueba cada letra mide un cuadrado y los
/// íconos salen como cajas.
Future<void> cargarTipografias() async {
  await cargarFuentesReales();
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++, dir = dir.parent) {
    final iconos = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (iconos.existsSync()) {
      final bytes = iconos.readAsBytesSync();
      final cargador = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
      return;
    }
  }
}

/// Los anuncios que la app le manda al lector de pantalla.
List<String> escucharAnuncios(WidgetTester tester) {
  final anuncios = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
    SystemChannels.accessibility,
    (dynamic mensaje) async {
      if (mensaje is Map && mensaje['type'] == 'announce') {
        anuncios.add((mensaje['data'] as Map)['message'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      null,
    ),
  );
  return anuncios;
}

/// Si el `EditableText` del [campo] (un `TextField`) tiene el foco.
bool campoConFoco(WidgetTester tester, Finder campo) {
  final editable = find.descendant(of: campo, matching: find.byType(EditableText));
  return tester.widget<EditableText>(editable).focusNode.hasFocus;
}

/// Quién tiene el foco: `campo#n` para un campo de texto (n = su posición) o el primer texto que
/// tiene adentro (el rótulo de un botón, de un chip…).
String quienTieneElFoco(WidgetTester tester) {
  final contexto = FocusManager.instance.primaryFocus?.context;
  if (contexto == null) return '(nadie)';
  // El nodo de foco de un campo cuelga de un `Focus` que está dentro de su `EditableText`.
  final editable = contexto.findAncestorWidgetOfExactType<EditableText>();
  if (editable != null || contexto.widget is EditableText) {
    final buscado = editable ?? contexto.widget;
    final campos = find.byType(EditableText).evaluate().toList();
    final n = campos.indexWhere((e) => identical(e.widget, buscado));
    return 'campo#$n';
  }
  String? texto;
  void buscar(Element e) {
    if (texto != null) return;
    final w = e.widget;
    if (w is Text && (w.data ?? '').isNotEmpty) {
      texto = w.data;
      return;
    }
    e.visitChildren(buscar);
  }

  (contexto as Element).visitChildren(buscar);
  return texto ?? contexto.widget.runtimeType.toString();
}

/// La raíz de la captura y la pantalla de partida de [abrirEdicionQa].
class _AnfitrionEdicion extends StatelessWidget {
  const _AnfitrionEdicion();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () =>
            ModificarUbicacionPage.abrir(context, colportorId: 'col-1', ubicacionId: 'ubi-1'),
        child: const Text('abrir'),
      ),
    ),
  );
}

/// Abre la edición de «Av. Italia 1234» como `abrirEdicion` del arnés de #307, más la conexión (07·03
/// «Guardado sin conexión») y la raíz de captura de esta QA.
Future<RepoEdicionFalso> abrirEdicionQa(
  WidgetTester tester, {
  Size tamano = const Size(360, 640),
  double escala = 1,
  double barraSuperior = 24,
  double barraInferior = 0,
  TipoConexion? conexion,
  RepoEdicionFalso? repo,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: barraSuperior, bottom: barraInferior);
  tester.view.viewPadding = FakeViewPadding(top: barraSuperior, bottom: barraInferior);
  addTearDown(tester.view.reset);
  final repoEdicion = repo ?? RepoEdicionFalso(ubicacionGuardada());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overridesAlta(
          gps: GpsFalso(),
          geocodificador: GeocodificadorFalso(
            (_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1250'),
          ),
          ciudades: CiudadesFalsas(),
          repo: repoEdicion,
          ahora: DateTime.utc(2026, 10, 2, 12),
          mapa: FabricaMapaFalsa(),
        ),
        if (conexion != null) conexionProvider.overrideWith((ref) => Stream.value(conexion)),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => RepaintBoundary(
          key: raizQa,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
        ),
        home: const _AnfitrionEdicion(),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return repoEdicion;
}
