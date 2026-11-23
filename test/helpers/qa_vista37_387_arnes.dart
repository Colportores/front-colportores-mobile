// Arnés del QA de la vista 37 (#387): fuentes reales, capturas PNG (solo con `--dart-define=QA_CAPTURAS=true`),
// el interruptor de los tests que documentan un hallazgo (`--dart-define=QA_HALLAZGOS=true`) y un armado
// que se queda cargando.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/pedidos/domain/entities/armado_del_pedido.dart';
import 'package:colportores_mobile/features/pedidos/domain/repositories/armado_del_pedido_repository.dart';
import 'package:colportores_mobile/features/pedidos/presentation/pages/pedir_pedido_page.dart';
import 'package:colportores_mobile/features/pedidos/presentation/providers/pedidos_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OffsetLayer;
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'deuda_casa_arnes.dart' show ConexionFija, overridesDeDeuda;
import 'pedidos_arnes.dart';

/// Los tamaños de la matriz de QA: el chico y el grande.
const telefonoChico37 = Size(360, 640);
const telefonoGrande37 = Size(412, 915);

const conCapturas37 = bool.fromEnvironment('QA_CAPTURAS');

/// Los tests de hallazgo corren solo con `QA_HALLAZGOS=true`; sin ella van con `skip`.
const verHallazgos37 = bool.fromEnvironment('QA_HALLAZGOS');

/// Carga Inter, SourceSerif4 y JetBrainsMono de `assets/fonts/` y los íconos de Material: sin eso
/// `flutter_test` dibuja cajas y mide el texto con Ahem.
Future<void> cargarFuentes37(WidgetTester tester) async {
  await tester.runAsync(() async {
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
  });
}

/// Una captura PNG de todo lo que se ve en `.dart_tool/qa_capturas/387_<nombre>.png`.
Future<void> capturar37(WidgetTester tester, String nombre) async {
  if (!conCapturas37) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/387_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Un armado cuyos productos no llegan hasta que el test los suelta (el «cargando» de 37A).
final class ArmadoQueEspera implements ArmadoDelPedidoRepository {
  final productos = Completer<List<ProductoPedible>>();

  @override
  Stream<List<ProductoPedible>> observarProductos(String colportorId) async* {
    yield await productos.future;
  }

  @override
  Stream<Map<String, String>> observarNombres() => Stream.value(const {});

  @override
  Stream<ContextoLocalDelPedido> observarContexto(String colportorId, DateTime hoy) =>
      Stream.value(const ContextoLocalDelPedido(librosPorEntregar: 4));
}

/// Un producto más de [n] para las listas largas.
ProductoPedible productoNumero37(int n, {String? nombre}) => ProductoPedible(
  id: 'p-$n',
  nombre: nombre ?? 'Libro número $n',
  categoriaDelCatalogo: CategoriaDeProducto.bonificables,
  precioDeCompraCentavos: 100000 + n,
  stock: n,
  esBonificable: true,
);

/// Monta «Nuevo pedido» directo (sin pantalla de abajo) con un armado que se queda cargando.
Future<void> montarPedirCargando(
  WidgetTester tester,
  ArnesDePedidos arnes,
  ArmadoQueEspera armado, {
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pedidoRepositoryProvider.overrideWithValue(arnes.pedidos),
        armadoDelPedidoRepositoryProvider.overrideWithValue(armado),
        resumenDeCuentaRepositoryProvider.overrideWithValue(arnes.cuenta),
        ...overridesDeDeuda(arnes.repoDeDeuda),
        relojPedidoProvider.overrideWithValue(() => ahoraLocal),
        generadorIdPedidoProvider.overrideWithValue(arnes.generarId),
        monitorConectividadProvider.overrideWithValue(const ConexionFija(TipoConexion.wifi)),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const PedirPedidoPage(colportorId: 'col-1'),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}
