// Arnés del QA de la vista 25 (Sincronización y respaldo, HU-SYNC-007 y HU-SYNC-008, #174, PR #489):
// arma cada artboard del canvas (25-01 a 25-11) y los estados que el canvas no dibuja sobre los
// falsos de `sincronizacion_falsos.dart`, con la raíz capturable para las imágenes.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/sincronizacion/domain/entities/estado_sincronizacion.dart';
import 'package:colportores_mobile/features/sincronizacion/presentation/pages/sincronizacion_page.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sincronizacion_falsos.dart';

/// Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true`.
const conCapturas25 = bool.fromEnvironment('QA_CAPTURAS');

/// Los dos tamaños del proyecto (móvil) y los dos tamaños de texto.
const t360x640 = Size(360, 640);
const t412x915 = Size(412, 915);
const tamanos25 = [t360x640, t412x915];
const escalas25 = [1.0, 2.0];

final raiz25 = GlobalKey();

/// Los estados que una persona puede ver.
enum Estado25 {
  a01AlDia,
  a02Pendientes,
  a03Actualizando,
  a04Actualizado,
  a05SinConexion,
  a06ConError,
  a07Detalle,
  a08ModoAhorro,
  a09HojaDatos,
  a10ErrorAlActualizar,
  a11SinRespaldo,
  cargando,
  errorDeLectura,
  errorDeFallidas,
  sesionSinRenovar,
  muchasPendientes,
  muchasFallidas,
  detalleLargo,
}

String nombre25(Estado25 e, Size t, double escala) =>
    '${e.name} · ${t.width.toInt()}×${t.height.toInt()} · texto ${escala == 1 ? '100' : '200'} %';

final _ahora = DateTime(2026, 10, 26, 14, 35);
final _hace3Min = _ahora.subtract(const Duration(minutes: 3));
final _hace2H = _ahora.subtract(const Duration(hours: 2));
final _respaldoHoy = DateTime(2026, 10, 26, 3, 10);
final _respaldoAyer = DateTime(2026, 10, 25, 3, 10);

List<OperacionFallida> dosFallidas25() => [
  operacionFallida(),
  operacionFallida(
    id: 'op-2',
    tabla: 'cobranza',
    fecha: DateTime(2026, 10, 22, 14, 21),
    error: 'Depende de la venta de arriba',
  ),
];

/// Las cuarenta rechazadas con motivos larguísimos y tablas de todo tipo.
List<OperacionFallida> cuarentaFallidas25() => [
  for (var i = 0; i < 40; i++)
    operacionFallida(
      id: 'op-$i',
      tabla: const ['venta', 'cobranza', 'ubicacion_par_decidido', 'house_status', 'raro_x'][i % 5],
      tipo: TipoOperacion.values[i % 3],
      fecha: DateTime(2026, 10, 22, 14, i % 60),
      error: i.isEven
          ? 'El servidor rechazó el dato porque la regla ${'de negocio muy larga ' * 6}no se cumple'
          : '',
    ),
];

TelefonoSync telefono25(Estado25 e) => switch (e) {
  Estado25.a01AlDia => TelefonoSync(
    estado: EstadoSincronizacion(
      ultimoEnvio: _hace3Min,
      ultimaActualizacion: _hace3Min,
      ultimoRespaldo: _respaldoHoy,
    ),
    respaldoConfigurado: true,
  ),
  Estado25.a02Pendientes || Estado25.a03Actualizando || Estado25.a05SinConexion => TelefonoSync(
    estado: EstadoSincronizacion(
      pendientes: 3,
      ultimoEnvio: _hace2H,
      ultimaActualizacion: _hace2H,
      ultimoRespaldo: _respaldoHoy,
    ),
    conexion: e == Estado25.a05SinConexion ? TipoConexion.sinConexion : TipoConexion.wifi,
    respaldoConfigurado: true,
  ),
  Estado25.a04Actualizado => TelefonoSync(
    estado: EstadoSincronizacion(
      pendientes: 3,
      ultimoEnvio: _hace2H,
      ultimaActualizacion: _hace2H,
      ultimoRespaldo: _respaldoHoy,
    ),
    respaldoConfigurado: true,
  ),
  Estado25.a06ConError || Estado25.a07Detalle || Estado25.errorDeFallidas => TelefonoSync(
    estado: EstadoSincronizacion(
      invalidas: 2,
      ultimoEnvio: _hace3Min,
      ultimaActualizacion: _hace3Min,
      ultimoRespaldo: _respaldoHoy,
    ),
    fallidas: dosFallidas25(),
    respaldoConfigurado: true,
  ),
  Estado25.a08ModoAhorro || Estado25.a09HojaDatos => TelefonoSync(
    estado: EstadoSincronizacion(
      ultimoEnvio: _ahora.subtract(const Duration(minutes: 1)),
      ultimaActualizacion: DateTime(2026, 10, 25, 21),
      ultimoRespaldo: _respaldoAyer,
      actualizacionEnEspera: true,
    ),
    conexion: TipoConexion.datosMoviles,
    modoAhorro: true,
    respaldoConfigurado: true,
  ),
  Estado25.a10ErrorAlActualizar => TelefonoSync(
    estado: EstadoSincronizacion(
      pendientes: 3,
      ultimoEnvio: _hace2H,
      ultimaActualizacion: _hace2H,
      ultimoRespaldo: _respaldoHoy,
    ),
    respaldoConfigurado: true,
  ),
  Estado25.a11SinRespaldo => TelefonoSync(
    estado: EstadoSincronizacion(ultimoEnvio: _hace3Min, ultimaActualizacion: _hace3Min),
  ),
  Estado25.cargando => TelefonoSync(),
  Estado25.errorDeLectura => TelefonoSync(),
  Estado25.sesionSinRenovar => TelefonoSync(
    estado: EstadoSincronizacion(
      pendientes: 3,
      ultimoEnvio: _hace2H,
      ultimaActualizacion: _hace2H,
      ultimoRespaldo: _respaldoHoy,
      sesionSinRenovar: true,
    ),
    respaldoConfigurado: true,
  ),
  Estado25.muchasPendientes => TelefonoSync(
    estado: EstadoSincronizacion(
      pendientes: 1234,
      ultimoEnvio: _hace2H,
      ultimaActualizacion: _hace2H,
      ultimoRespaldo: _respaldoHoy,
    ),
    respaldoConfigurado: true,
  ),
  Estado25.muchasFallidas => TelefonoSync(
    estado: EstadoSincronizacion(
      invalidas: 40,
      pendientes: 7,
      ultimoEnvio: _hace3Min,
      ultimaActualizacion: _hace3Min,
      ultimoRespaldo: _respaldoHoy,
    ),
    fallidas: cuarentaFallidas25(),
    respaldoConfigurado: true,
  ),
  Estado25.detalleLargo => TelefonoSync(
    estado: EstadoSincronizacion(
      invalidas: 1,
      ultimoEnvio: _hace3Min,
      ultimaActualizacion: _hace3Min,
      ultimoRespaldo: _respaldoHoy,
    ),
    fallidas: [
      operacionFallida(
        error:
            'El servidor rechazó el dato porque ${'una regla de negocio muy larga ' * 20}no se cumple',
      ),
    ],
    respaldoConfigurado: true,
  ),
};

/// Monta la página con [telefono] en el tamaño y la escala pedidos, con la raíz capturable.
Future<void> montar25(
  WidgetTester tester,
  TelefonoSync telefono, {
  Size tamano = const Size(390, 844),
  double escala = 1.0,
  TextDirection? direccion,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: telefono.overrides,
      child: RepaintBoundary(
        key: raiz25,
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: const SincronizacionPage(),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Lleva la pantalla al estado [e]: lo monta y hace lo que una persona hace para llegar.
Future<TelefonoSync> llegar25(
  WidgetTester tester,
  Estado25 e, {
  Size tamano = const Size(390, 844),
  double escala = 1.0,
}) async {
  final t = telefono25(e);
  switch (e) {
    case Estado25.cargando:
      t.servicio.lecturaLenta = Completer<void>();
    case Estado25.errorDeLectura:
      t.servicio.fallaAlLeer = true;
    case Estado25.errorDeFallidas:
      t.servicio.fallaAlLeerFallidas = true;
    case Estado25.a03Actualizando:
      t.servicio.actualizacionEnCurso = Completer();
    case Estado25.a04Actualizado:
      t.servicio.resultado = const ActualizacionCompleta(enviadas: 3, recibidas: 12);
    case Estado25.a10ErrorAlActualizar:
      t.servicio.resultado = const ActualizacionFallida(MotivoFallaActualizacion.servidor);
    default:
  }
  await montar25(tester, t, tamano: tamano, escala: escala);
  switch (e) {
    case Estado25.a03Actualizando:
      await tester.tap(botonActualizar);
      await tester.pump();
    case Estado25.a04Actualizado:
      await tester.tap(botonActualizar);
      await tester.pump();
      t.servicio.emitir(
        EstadoSincronizacion(
          ultimoEnvio: _ahora,
          ultimaActualizacion: _ahora,
          ultimoRespaldo: _ahora,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
    case Estado25.a10ErrorAlActualizar:
      await tester.tap(botonActualizar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    case Estado25.a07Detalle || Estado25.detalleLargo:
      final tarjeta = find.text('Venta del 22/10');
      await tester.ensureVisible(tarjeta);
      await tester.tap(tarjeta);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    case Estado25.a09HojaDatos:
      await tester.tap(botonActualizar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    default:
  }
  return t;
}

/// Las cuatro guías de accesibilidad de Flutter. Las medidas de contraste se toman con la fuente de
/// prueba (con las reales dan falsos negativos).
Future<void> guias25(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// Carga Inter, Source Serif, JetBrains Mono y los íconos de Material (sin ellos todo son cajas).
Future<void> cargarFuentes25(WidgetTester tester) => tester.runAsync(() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await cargador.load();
  }
  final raizFlutter =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
  for (final ruta in [
    '$raizFlutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    '${Directory(Platform.resolvedExecutable).parent.parent.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]) {
    final archivo = File(ruta);
    if (archivo.existsSync()) {
      final cargador = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(archivo.readAsBytesSync().buffer)));
      await cargador.load();
      return;
    }
  }
});

/// Una captura PNG de la pantalla entera (hojas incluidas) en `.dart_tool/qa_capturas/174_<nombre>.png`,
/// solo con `QA_CAPTURAS`.
Future<void> capturar25(WidgetTester tester, String nombre) async {
  if (!conCapturas25) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/174_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
