// Arnés del QA de #307 / PR #321 («Abrir de nuevo» a la vista, vista 07 «Modificar ubicación»,
// HU-UBI-004): monta la edición con lo que los arneses de la vista no dejan mover juntos: la barra de
// estado, la barra de abajo del sistema (navegación por 3 botones), el teclado abierto y la escala del
// texto, y llega al aviso «cambió mientras la editabas».
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'alta_ubicacion_falsos.dart';
import 'mapa_base_falso.dart';
import 'modificar_ubicacion_falsos.dart';

/// Los dos teléfonos chicos del QA.
const telefono360x640 = Size(360, 640);
const telefono320x568 = Size(320, 568);

/// La barra de estado de un Android común, la barra de abajo de la navegación por 3 botones y el
/// teclado abierto (en dp).
const barraDeEstado = 24.0;
const barraDeTresBotones = 48.0;
const tecladoAbierto = 300.0;

/// La raíz de las capturas.
final raizCaptura = GlobalKey();

/// Lo que dejó montado [abrirEdicion].
class EdicionMontada {
  EdicionMontada({required this.repo, required this.mapa, required this.tamano});

  final RepoEdicionFalso repo;
  final FabricaMapaFalsa mapa;
  final Size tamano;
}

class _Anfitrion extends StatelessWidget {
  const _Anfitrion();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () => ModificarUbicacionPage.abrir(
          context,
          colportorId: 'col-1',
          ubicacionId: 'ubi-1',
          alDarDeBaja: () {},
        ),
        child: const Text('abrir'),
      ),
    ),
  );
}

Future<void> asentar(WidgetTester tester, [int veces = 10]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Abre la edición de «Av. Italia 1234» con el sistema de un Android: [barraDeEstado] arriba y
/// [barraInferior] abajo (la navegación por 3 botones, ya con el borde a borde de Android 15).
Future<EdicionMontada> abrirEdicion(
  WidgetTester tester, {
  Size tamano = telefono360x640,
  double escala = 1,
  double barraInferior = 0,
  double barraSuperior = barraDeEstado,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: barraSuperior, bottom: barraInferior);
  tester.view.viewPadding = FakeViewPadding(top: barraSuperior, bottom: barraInferior);
  addTearDown(tester.view.reset);
  final montada = EdicionMontada(
    repo: RepoEdicionFalso(ubicacionGuardada()),
    mapa: FabricaMapaFalsa(),
    tamano: tamano,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesAlta(
        gps: GpsFalso(),
        geocodificador: GeocodificadorFalso(
          (_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1250'),
        ),
        ciudades: CiudadesFalsas(),
        repo: montada.repo,
        ahora: DateTime.utc(2026, 10, 2, 12),
        mapa: montada.mapa,
      ),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => RepaintBoundary(
          key: raizCaptura,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
        ),
        home: const _Anfitrion(),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await asentar(tester);
  return montada;
}

/// Abre el teclado: el sistema ya descuenta la barra de abajo de `padding` (la deja en `viewPadding`).
Future<void> abrirTeclado(WidgetTester tester, {double alto = tecladoAbierto}) async {
  tester.view.viewInsets = FakeViewPadding(bottom: alto);
  tester.view.padding = FakeViewPadding(top: tester.view.padding.top);
  await asentar(tester);
}

Future<void> cerrarTeclado(WidgetTester tester) async {
  tester.view.resetViewInsets();
  tester.view.padding = FakeViewPadding(
    top: tester.view.viewPadding.top,
    bottom: tester.view.viewPadding.bottom,
  );
  await asentar(tester);
}

Finder get botonGuardar => find.widgetWithText(FilledButton, TextosModificar.guardarCambios);

Finder get campoNumero => find.byType(TextField).at(1);

/// Lo que se desplaza de la hoja de edición.
Finder get zonaDesplazable => find
    .descendant(of: find.byType(HojaModificarDatos), matching: find.byType(SingleChildScrollView))
    .first;

Rect rectZona(WidgetTester tester) => tester.getRect(zonaDesplazable);

/// Llega al aviso «cambió mientras la editabas»: escribe el número (con el teclado abierto si
/// [conTeclado]) y guarda con la ubicación cambiada por debajo.
Future<void> fallarPorCambio(
  WidgetTester tester,
  EdicionMontada m, {
  bool conTeclado = false,
  String numero = '1238',
  int hora = 9,
}) async {
  if (conTeclado) await abrirTeclado(tester);
  await tester.enterText(campoNumero, numero);
  await asentar(tester);
  m.repo.actual = ubicacionGuardada(actualizada: DateTime.utc(2026, 10, 1, hora));
  await tester.tap(botonGuardar);
  await asentar(tester);
  expect(find.textContaining('cambió mientras la editabas'), findsOneWidget);
}

/// Una captura PNG de la pantalla en `.dart_tool/qa_capturas/` (gitignored, fuera del commit).
Future<void> capturar(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raizCaptura));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/321_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
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
