// Arnés de los tests de QA de #561 (vista 26 «Precios», etiqueta de cada producto por su categoría):
// monta la pantalla sola con la réplica falsa, carga las fuentes reales del proyecto (sin ellas
// `flutter_test` pinta cajas Ahem y las medidas de layout mienten) y saca capturas PNG a
// `.dart_tool/qa_capturas/` (gitignored: nunca se commitean), solo con `--dart-define=QA_CAPTURAS=true`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/catalogo/presentation/pages/precios_page.dart';
import 'package:colportores_mobile/features/catalogo/presentation/providers/precios_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'alta_ubicacion_falsos.dart';
import 'precios_falsos.dart';
import 'ubicacion_colportor_falsos.dart';

const conCapturas561 = bool.fromEnvironment('QA_CAPTURAS');

/// Tamaños lógicos de la matriz de QA: el chico y el grande.
const telefonoChico561 = Size(360, 640);
const telefonoGrande561 = Size(412, 915);

final raizCaptura561 = GlobalKey();

/// Carga Inter, SourceSerif4 y JetBrainsMono de `assets/fonts/` y los íconos de Material.
Future<void> cargarFuentes561() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await cargador.load();
  }
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
}

/// Un catálogo con los casos que mezclan la categoría con las marcas sueltas y los textos límite.
CatalogoLocal catalogoLimite561() {
  const productos = <ProductoDelCatalogo>[
    ProductoDelCatalogo(
      id: 'b1',
      nombre: 'Salud y Hogar',
      categoria: CategoriaDeProducto.bonificables,
      esBonificable: true,
      codigoEditor: 'SH-12',
    ),
    // P2: la marca suelta `es_misionero` no cambia la pestaña ni la etiqueta de un bonificable.
    ProductoDelCatalogo(
      id: 'b2',
      nombre: 'Bonificable con marca misionera',
      categoria: CategoriaDeProducto.bonificables,
      esBonificable: true,
      esMisionero: true,
    ),
    // P2: un espiritual con `es_misionero` sigue en «Libros» con «✝ Espiritual».
    ProductoDelCatalogo(
      id: 'e1',
      nombre: 'Espiritual con marca misionera',
      categoria: CategoriaDeProducto.espirituales,
      esMisionero: true,
    ),
    ProductoDelCatalogo(
      id: 'e2',
      nombre: 'El Deseado de todas las gentes',
      categoria: CategoriaDeProducto.espirituales,
      codigoEditor: 'DG-01',
    ),
    // Texto largo: nombre de 150 caracteres, código largo y las dos etiquetas.
    ProductoDelCatalogo(
      id: 'e3',
      nombre:
          'Un título larguísimo de libro que ocupa varias líneas aun en un teléfono grande, con '
          'subtítulo, edición revisada y aumentada, tomo tercero de la serie completa',
      categoria: CategoriaDeProducto.espirituales,
      esBonificable: true,
      codigoEditor: 'ACES-0214-EDICION-ESPECIAL-2026-TOMO-3',
    ),
    // Sin la marca `es_misionero`: la categoría alcanza para estar en «Misioneros».
    ProductoDelCatalogo(
      id: 'm1',
      nombre: 'Misionero sin marca',
      categoria: CategoriaDeProducto.misioneros,
    ),
    ProductoDelCatalogo(
      id: 'm2',
      nombre: 'Misionero bonificable',
      categoria: CategoriaDeProducto.misioneros,
      esBonificable: true,
      esMisionero: true,
    ),
    ProductoDelCatalogo(
      id: 'r1',
      nombre: 'Revista Vida y Salud',
      categoria: CategoriaDeProducto.revistas,
    ),
    ProductoDelCatalogo(
      id: 'r2',
      nombre: 'Revista bonificable',
      categoria: CategoriaDeProducto.revistas,
      esBonificable: true,
    ),
    // Lo que no se ofrece aunque tenga precio.
    ProductoDelCatalogo(
      id: 'x1',
      nombre: 'Material bonificable',
      categoria: CategoriaDeProducto.material,
      esBonificable: true,
    ),
    ProductoDelCatalogo(
      id: 'x2',
      nombre: 'Sin categoría bonificable',
      categoria: CategoriaDeProducto.otra,
      esBonificable: true,
      esMisionero: true,
    ),
    ProductoDelCatalogo(
      id: 'x3',
      nombre: 'Espiritual dado de baja',
      categoria: CategoriaDeProducto.espirituales,
      dadoDeBaja: true,
    ),
  ];
  return CatalogoLocal(
    productos: productos,
    generales: [
      for (final p in productos)
        PrecioDelCatalogo(
          id: 'g-${p.id}',
          productoId: p.id,
          centavos: 100000,
          validoDesde: '2026-01-01',
        ),
    ],
  );
}

/// Todo lo que el test controla de la pantalla.
final class Entorno561 {
  Entorno561({ConsultaDePreciosFalsa? repo})
    : repo = repo ?? ConsultaDePreciosFalsa(catalogoLimite561());

  final ConsultaDePreciosFalsa repo;
  final fuente = FuenteDeCiudadesFalsa();
  final gps = GpsFalso();
  final alta = CiudadesFalsas();
  final fecha = FechaDeLosPreciosFalsa(DateTime(2026, 10, 22, 18));

  List<Override> get overrides => [
    consultaDePreciosRepositoryProvider.overrideWithValue(repo),
    fuenteDeCiudadesParaPreciosProvider.overrideWithValue(fuente),
    fechaDeLosPreciosProvider.overrideWithValue(fecha),
    diasDeAntiguedadDePreciosProvider.overrideWithValue(DiasFalsos(15)),
    relojPreciosProvider.overrideWithValue(() => DateTime(2026, 10, 28, 10)),
    proveedorGpsProvider.overrideWithValue(gps),
    ubicacionColportorDeGps(gps),
    ciudadesParaAltaProvider.overrideWithValue(alta),
    conexionProvider.overrideWith((ref) => Stream.value(TipoConexion.wifi)),
  ];
}

Future<void> asentar561(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Monta Precios sola a [tamano] y [escala].
Future<void> montar561(
  WidgetTester tester,
  Entorno561 e, {
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: e.overrides,
      child: RepaintBoundary(
        key: raizCaptura561,
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: const PreciosPage(colportorId: 'col-1'),
        ),
      ),
    ),
  );
  await asentar561(tester);
}

Finder chip561(String nombre) => find.byKey(Key('precios_chip_$nombre'));

/// Toca una pestaña: la lleva a la vista (los chips van dentro de la lista y a 200 % quedan debajo
/// del primer cuadro) y verifica que el toque cae dentro de la pantalla.
Future<void> irA561(WidgetTester tester, String chip) async {
  final f = chip561(chip);
  final alto = tester.view.physicalSize.height;
  for (var i = 0; i < 40; i++) {
    await tester.drag(find.byKey(const Key('precios_scroll')), const Offset(0, 2000));
    await tester.pump();
  }
  expect(f, findsOneWidget);
  for (var i = 0; i < 8 && tester.getCenter(f).dy > alto - 80; i++) {
    await tester.drag(
      find.byKey(const Key('precios_scroll')),
      Offset(0, -(tester.getCenter(f).dy - alto / 3)),
    );
    await tester.pump();
  }
  final c = tester.getCenter(f);
  expect(c.dy > 0 && c.dy < alto, isTrue, reason: 'el chip $chip quedó fuera de la pantalla: $c');
  await tester.tap(f);
  await asentar561(tester);
}

/// Desliza la lista hasta que [f] se construya (las filas se arman a medida que se ven).
Future<void> hasta561(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 60 && f.evaluate().isEmpty; i++) {
    await tester.drag(find.byKey(const Key('precios_scroll')), const Offset(0, -300));
    await tester.pump();
  }
  expect(f, findsOneWidget, reason: 'la lista no llegó a construirlo');
}

/// Vuelve al principio de la lista.
Future<void> alInicio561(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.drag(find.byKey(const Key('precios_scroll')), const Offset(0, 2000));
    await tester.pump();
  }
}

/// Una captura PNG en `.dart_tool/qa_capturas/561_<nombre>.png` (solo con `QA_CAPTURAS=true`).
Future<void> capturar561(WidgetTester tester, String nombre) async {
  if (!conCapturas561) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raizCaptura561));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/561_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Contraste WCAG entre dos colores opacos.
double contraste561(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final claro = la > lb ? la : lb;
  final oscuro = la > lb ? lb : la;
  return (claro + 0.05) / (oscuro + 0.05);
}

/// Ningún texto visible se sale de la pantalla por los costados.
void expectSinTextoFueraDeLosCostados561(WidgetTester tester, Size tamano) {
  for (final e in find.byType(RichText).evaluate()) {
    final render = e.renderObject;
    if (render is! RenderBox || !render.attached || !render.hasSize) continue;
    var enDesplazamientoHorizontal = false;
    e.visitAncestorElements((a) {
      final w = a.widget;
      if (w is Scrollable && w.axis == Axis.horizontal) enDesplazamientoHorizontal = true;
      return !enDesplazamientoHorizontal;
    });
    if (enDesplazamientoHorizontal) continue;
    final r = render.localToGlobal(Offset.zero) & render.size;
    expect(
      r.left >= -0.5 && r.right <= tamano.width + 0.5,
      isTrue,
      reason: 'un texto se sale de la pantalla: ${(e.widget as RichText).text.toPlainText()} $r',
    );
  }
}
