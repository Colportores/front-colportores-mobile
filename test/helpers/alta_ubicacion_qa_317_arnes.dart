// Arnés del QA de #305 / PR #317 («Registrar» fijo al pie de la hoja del alta, vista 03): monta el alta
// con lo que el arnés común (`alta_ubicacion_qa_arnes.dart`) no deja mover: las ciudades de la campaña,
// la barra de abajo del sistema, el mapa falso para marcar un punto y la escala del texto cambiante
// (rotar o cambiar el tamaño de la letra con la hoja abierta).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/situacion_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:dartz/dartz.dart' show Right;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'alta_ubicacion_falsos.dart';
import 'alta_ubicacion_qa_arnes.dart';
import 'mapa_base_falso.dart';

export 'alta_ubicacion_qa_arnes.dart' show asentar, gpsSinPermiso, situacionSinConexion, tocar;

/// Un teléfono chico y uno grande, los dos tamaños del QA.
const telefonoChico = Size(360, 640);
const telefonoGrande = Size(412, 915);

/// La barra de estado de un Android común y el teclado abierto (en dp).
const barraDeEstado = 24.0;
const tecladoAbierto = 300.0;

/// Lo que dejó montado [abrirAlta].
class AltaMontada {
  AltaMontada({
    required this.repo,
    required this.mapa,
    required this.gps,
    required this.geocodificador,
    required this.ciudades,
    required this.salidas,
    required this.escala,
  });

  final RepoAltaFalso repo;
  final FabricaMapaFalsa mapa;
  final GpsFalso gps;
  final GeocodificadorFalso geocodificador;
  final CiudadesFalsas ciudades;
  final List<SalidaAltaUbicacion?> salidas;

  /// La escala del texto: cambiarla con la hoja abierta es lo mismo que cambiar la letra del teléfono.
  final ValueNotifier<double> escala;
}

/// La raíz de las capturas.
final raizCaptura = GlobalKey();

class _Anfitrion extends StatelessWidget {
  const _Anfitrion(this.salidas);

  final List<SalidaAltaUbicacion?> salidas;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () async =>
            salidas.add(await AltaUbicacionPage.abrir(context, colportorId: 'col-1')),
        child: const Text('abrir'),
      ),
    ),
  );
}

/// Abre el alta con el sistema de un Android: [barraDeEstado] arriba, [barraInferior] abajo (la
/// navegación por gestos) y, si [teclado] es mayor que 0, el teclado ya abierto.
Future<AltaMontada> abrirAlta(
  WidgetTester tester, {
  Size tamano = telefonoChico,
  double escala = 1,
  double barraInferior = 0,
  double teclado = 0,
  GpsFalso? gps,
  CiudadesFalsas? ciudades,
  RepoAltaFalso? repo,
  GeocodificadorFalso? geocodificador,
  SituacionMapa? situacion,
  bool esperarAnimaciones = true,
  double barraSuperior = barraDeEstado,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: barraSuperior, bottom: barraInferior);
  tester.view.viewPadding = FakeViewPadding(top: barraSuperior, bottom: barraInferior);
  addTearDown(tester.view.reset);
  final montada = AltaMontada(
    repo: repo ?? RepoAltaFalso(),
    mapa: FabricaMapaFalsa(),
    gps: gps ?? GpsFalso(),
    geocodificador:
        geocodificador ??
        GeocodificadorFalso((_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1234')),
    ciudades: ciudades ?? CiudadesFalsas(),
    salidas: [],
    escala: ValueNotifier<double>(escala),
  );
  addTearDown(montada.escala.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesAlta(
        gps: montada.gps,
        geocodificador: montada.geocodificador,
        ciudades: montada.ciudades,
        repo: montada.repo,
        mapa: montada.mapa,
        ahora: DateTime.utc(2026, 10, 2, 12),
        situacion: situacion,
      ),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => RepaintBoundary(
          key: raizCaptura,
          child: ValueListenableBuilder<double>(
            valueListenable: montada.escala,
            builder: (context, valor, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(valor)),
              child: child!,
            ),
          ),
        ),
        home: _Anfitrion(montada.salidas),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await asentar(tester);
  // Con el GPS buscando hay un indicador que no termina: ahí solo se avanza un rato.
  if (esperarAnimaciones) await tester.pumpAndSettle();
  if (teclado > 0) await abrirTeclado(tester, teclado);
  return montada;
}

Future<void> abrirTeclado(WidgetTester tester, [double alto = tecladoAbierto]) async {
  tester.view.viewInsets = FakeViewPadding(bottom: alto);
  // Con el teclado el sistema ya descuenta la barra de abajo de `padding`.
  tester.view.padding = const FakeViewPadding(top: barraDeEstado);
  await tester.pumpAndSettle();
}

Future<void> cerrarTeclado(WidgetTester tester, {double barraInferior = 0}) async {
  tester.view.resetViewInsets();
  tester.view.padding = FakeViewPadding(top: barraDeEstado, bottom: barraInferior);
  await tester.pumpAndSettle();
}

/// La parte de la hoja que se desplaza.
Finder get desplazable =>
    find.descendant(of: find.byType(HojaAlta), matching: find.byType(SingleChildScrollView)).first;

/// El botón «Registrar» (o «Registrando…»).
Finder get botonRegistrarFijo => find.byWidgetPredicate(
  (w) =>
      w is FilledButton &&
      w.child is Text &&
      ((w.child! as Text).data == TextosAlta.registrar ||
          (w.child! as Text).data == TextosAlta.registrando),
);

Finder get campoCalle => find.byType(TextField).first;

Finder get campoNumero => find.byType(TextField).at(1);

bool registrarHabilitado(WidgetTester tester) =>
    tester.widget<FilledButton>(botonRegistrarFijo).onPressed != null;

/// Lo que se ve de la hoja que se desplaza: el rectángulo de su zona de scroll.
Rect zonaQueSeDesplaza(WidgetTester tester) => tester.getRect(desplazable);

/// Lleva la hoja que se desplaza hasta el final.
Future<void> irAlFinalDeLaHoja(WidgetTester tester) async {
  final scroll = tester.state<ScrollableState>(
    find.descendant(of: desplazable, matching: find.byType(Scrollable)).first,
  );
  scroll.position.jumpTo(scroll.position.maxScrollExtent);
  await tester.pump();
}

/// Lleva la hoja que se desplaza hasta arriba de todo.
Future<void> irAlPrincipioDeLaHoja(WidgetTester tester) async {
  final scroll = tester.state<ScrollableState>(
    find.descendant(of: desplazable, matching: find.byType(Scrollable)).first,
  );
  scroll.position.jumpTo(0);
  await tester.pump();
}

/// Una captura PNG de la pantalla en `.dart_tool/qa_capturas/` (gitignored, fuera del commit).
Future<void> capturar(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raizCaptura));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/317_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Carga los íconos de Material: sin ellos `flutter_test` pinta cuadrados en las capturas.
Future<void> cargarIconosParaCapturas(WidgetTester tester) async {
  await tester.runAsync(() async {
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
}

/// Los estados del canvas (vista 03) a los que se llega desde el alta.
enum EstadoAlta {
  gpsPreciso('03A · 01 GPS preciso'),
  sinGps('03A · 02 Sin GPS'),
  gpsImpreciso('03A · 03 GPS impreciso'),
  numeroEditado('03A · 04 Número editado'),
  sinGpsSinConexion('03A · 02 Sin GPS y sin conexión'),
  sinCiudades('03A · 02 Sin GPS y campaña sin ciudades');

  const EstadoAlta(this.rotulo);
  final String rotulo;
}

/// Monta el alta en el estado [estado] y, donde corresponde, elige «Casa» y escribe el número.
Future<AltaMontada> abrirEn(
  WidgetTester tester,
  EstadoAlta estado, {
  Size tamano = telefonoChico,
  double escala = 1,
  double barraInferior = 0,
  double teclado = 0,
  double barraSuperior = barraDeEstado,
}) async {
  final m = await abrirAlta(
    tester,
    barraSuperior: barraSuperior,
    tamano: tamano,
    escala: escala,
    barraInferior: barraInferior,
    gps: switch (estado) {
      EstadoAlta.sinGps || EstadoAlta.sinGpsSinConexion || EstadoAlta.sinCiudades => gpsSinPermiso,
      EstadoAlta.gpsImpreciso => GpsFalso(Right(lecturaGps(85))),
      _ => null,
    },
    ciudades: estado == EstadoAlta.sinCiudades
        ? CiudadesFalsas(propone: (_) => const CampaniaSinCiudades(), campania: const [])
        : null,
    situacion: estado == EstadoAlta.sinGpsSinConexion ? situacionSinConexion : null,
  );
  if (estado == EstadoAlta.numeroEditado) {
    await tester.enterText(campoNumero, '1238');
    await asentar(tester);
  }
  if (teclado > 0) await abrirTeclado(tester, teclado);
  return m;
}
