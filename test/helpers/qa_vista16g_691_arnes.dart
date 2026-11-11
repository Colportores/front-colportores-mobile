// Arnés del QA de la vista 16, artboards 16G (#691): la fila «Recuperar mi respaldo» de
// Configuración con la app entera, en los estados del canvas y en los que el canvas no dibuja.
//
// Capturas PNG con `--dart-define=QA_CAPTURAS=true`, en `.dart_tool/qa_capturas/` (gitignored).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/arranque/reinicio_de_raiz.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/respaldo/data/services/servicio_google.dart'
    show CuentaGoogle;
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart' show GoogleSignInExceptionCode;

import 'db_local_repository_en_memoria.dart';
import 'notificaciones_arnes.dart' as notif;
import 'recuperacion_arnes.dart';
import 'respaldo_drive_falsos.dart';

const conCapturas = bool.fromEnvironment('QA_CAPTURAS');

/// Los cuatro tamaños de la matriz: (nombre, ancho, alto, escala de texto).
const tamanos = <(String, double, double, double)>[
  ('360x640_1x', 360, 640, 1),
  ('360x640_2x', 360, 640, 2),
  ('412x915_1x', 412, 915, 1),
  ('412x915_2x', 412, 915, 2),
];

final asistente = find.byKey(const Key('recuperacion_pagina'));
final configuracion = find.byKey(const Key('configuracion_pagina'));
final abrirConfiguracion = find.byKey(const Key('inicio_configuracion'));
final atrasConfiguracion = find.byKey(const Key('configuracion_atras'));
final avisoNo = find.byKey(const Key('configuracion_recuperar_respaldo_no'));
final hojaConectar = find.byKey(const Key('drive_hoja_conectar'));
final conectarConGoogle = find.byKey(const Key('drive_conectar'));
final conectarAhoraNo = find.byKey(const Key('drive_ahora_no'));
final avisoCancelado = find.byKey(const Key('configuracion_drive_aviso_cancelado'));
final detalleFila = find.byKey(const Key('configuracion_recuperar_respaldo_detalle'));
final motivoFila = find.byKey(const Key('configuracion_recuperar_respaldo_motivo'));

bool _fuentesCargadas = false;

/// Carga las fuentes de `assets/fonts/` y los íconos de Material: sin esto `flutter_test` pinta cajas.
Future<void> cargarFuentesReales(WidgetTester tester) async {
  if (_fuentesCargadas) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    final raiz = Platform.environment['FLUTTER_ROOT'];
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final candidato = raiz != null
          ? File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          : File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (candidato.existsSync()) {
        final bytes = candidato.readAsBytesSync();
        final cargador = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await cargador.load();
        break;
      }
    }
  });
  _fuentesCargadas = true;
}

Future<void> asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await asentar(tester);
}

ProviderContainer raiz(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ColportoresApp)));

/// La app entera hasta Hoy, después de «Empezar sin recuperar» (el teléfono sigue sin datos).
Future<notif.Telefono> abrirApp(
  WidgetTester tester,
  ArnesRecuperacion arnes, {
  double ancho = 390,
  double alto = 844,
  double escala = 1,
  bool fuentesReales = true,
}) async {
  if (fuentesReales) await cargarFuentesReales(tester);
  final telefono = notif.Telefono();
  tester.view.physicalSize = Size(ancho, alto);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final dbDelTelefono = dbLocalYaPreparada();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ReiniciadorDeRaiz(
      overrides: () => [
        dbLocalRepositoryProvider.overrideWithValue(dbDelTelefono),
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
        ),
        authLocalDataSourceProvider.overrideWithValue(telefono.sesionGuardada),
        ...telefono.overrides,
        ...arnes.overridesDelAsistente,
      ],
      child: const ColportoresApp(),
    ),
  );
  await tester.pumpAndSettle();
  if (find.byKey(const Key('login_enviar')).evaluate().isNotEmpty) {
    await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
    await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
    await tester.ensureVisible(find.byKey(const Key('login_enviar')));
    await tester.tap(find.byKey(const Key('login_enviar')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  await empezarSinRecuperar(tester, cta2);
  if (notif.pedidoAhoraNo.evaluate().isNotEmpty) await tocar(tester, notif.pedidoAhoraNo);
  await tester.pumpAndSettle();
  expect(notif.principal, findsOneWidget);
  return telefono;
}

/// Hoy → engranaje → Configuración, con la fila a la vista.
Future<void> irAConfiguracion(WidgetTester tester) async {
  await tester.tap(abrirConfiguracion);
  // Sin `pumpAndSettle`: con el estado del Drive leyéndose, la fila «Cuenta Drive» gira.
  await asentar(tester);
  expect(configuracion, findsOneWidget);
  await tester.ensureVisible(filaRecuperarRespaldo);
  await tester.pump();
}

/// Los nueve estados que se miran en la matriz (tamaño × texto).
enum Estado16G {
  fila01('16G·01 fila con Drive'),
  hoja02('16G·02 hoja Antes de empezar'),
  fila03('16G·03 fila sin Drive'),
  conexion03('16G·03 hoja de conexión 16D·02'),
  cancelado03('16G·03 cancelado en Google 16D·07'),
  fila04('16G·04 apagada con el motivo'),
  errorDrive('Drive ilegible: aviso'),
  hayDatos('Cargó datos con la hoja abierta: aviso y apagada'),
  hojaCorreoLargo('16G·02 con correo largo');

  const Estado16G(this.rotulo);
  final String rotulo;
}

/// Deja la app en [estado], con Configuración abierta.
Future<void> armarEstado(WidgetTester tester, ArnesRecuperacion arnes, Estado16G estado) async {
  switch (estado) {
    case Estado16G.fila01:
      await conectarDriveDeLaApp(tester);
      await irAConfiguracion(tester);
    case Estado16G.hoja02:
      await conectarDriveDeLaApp(tester);
      await irAConfiguracion(tester);
      await tocar(tester, filaRecuperarRespaldo);
    case Estado16G.fila03:
      await irAConfiguracion(tester);
    case Estado16G.conexion03:
      await irAConfiguracion(tester);
      await tocar(tester, filaRecuperarRespaldo);
    case Estado16G.cancelado03:
      arnes.drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.canceled);
      await irAConfiguracion(tester);
      await tocar(tester, filaRecuperarRespaldo);
      await tocar(tester, conectarConGoogle);
    case Estado16G.fila04:
      arnes.lector.sinDatos = false;
      await irAConfiguracion(tester);
    case Estado16G.errorDrive:
      await conectarDriveDeLaApp(tester);
      arnes.drive.almacen.alLeer = true;
      raiz(tester).invalidate(estadoRespaldoDriveProvider);
      await irAConfiguracion(tester);
      await tocar(tester, filaRecuperarRespaldo);
    case Estado16G.hayDatos:
      await conectarDriveDeLaApp(tester);
      await irAConfiguracion(tester);
      await tocar(tester, filaRecuperarRespaldo);
      arnes.lector.sinDatos = false;
      await tocar(tester, hojaRecuperarEmpezar);
    case Estado16G.hojaCorreoLargo:
      arnes.drive.google.cuenta = const CuentaGoogle(id: 'g-1', email: _correoLargo);
      await conectarDriveDeLaApp(tester);
      await irAConfiguracion(tester);
      await tocar(tester, filaRecuperarRespaldo);
  }
}

/// Una captura PNG de toda la vista (incluye las hojas modales) en
/// `.dart_tool/qa_capturas/691_<nombre>.png`. El nombre sin `:` ni `·`.
Future<void> capturar691(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/691_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Un correo largo y de un solo renglón, sin espacios donde cortar.
const _correoLargo =
    'colportora.de.la.zona.cerro.norte.primavera.dos.mil.veintiseis@dominio-muy-largo.example.com';
