// Arnés del QA de «Cuenta Drive» (HU-SYNC-004, vista 16, 16D·01 a 16D·10, #184): monta la app real
// con sesión iniciada, abre Configuración en un teléfono de verdad (360×640 o 412×915, texto 1,0 o
// 2,0) y deja la pantalla en cada estado del canvas siguiendo lo que haría una persona. Las capturas
// solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/respaldo/data/services/servicio_google.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'db_local_repository_en_memoria.dart';
import 'qa_vista23_408_arnes.dart' show cargarFuentes408, conCapturas408;
import 'respaldo_drive_falsos.dart';

export 'qa_vista23_408_arnes.dart' show conCapturas408, usarFuentesReales408;

const chico184 = Size(360, 640);
const grande184 = Size(412, 915);

/// Cada estado del canvas (más los de la HU que el canvas no dibuja) y cómo se llega a él.
enum Estado184 {
  sinConectar('16D·01 Sin conectar'),
  previa('16D·02 Antes de conectar'),
  conectando('16D·03 Conectando'),
  conectada('16D·04 Conectada'),
  desconectar('16D·05 Desconectar'),
  revocado('16D·06 Permiso revocado'),
  cancelo('16D·07 Canceló en Google'),
  sinConexion('16D·08 Sin conexión'),
  error('16D·09 Error'),
  sinEspacio('16D·10 Drive sin espacio'),
  cargando('HU cargando'),
  errorLectura('HU error de lectura'),
  errorDesconectar('HU error al desconectar');

  const Estado184(this.rotulo);

  final String rotulo;

  /// El estado muestra una hoja (modal) y no solo la fila.
  bool get conHoja => switch (this) {
    previa || conectando || desconectar || sinConexion || error || errorDesconectar => true,
    _ => false,
  };
}

final fila184 = find.byKey(const Key('configuracion_drive_fila'));
final hojaConectar184 = find.byKey(const Key('drive_hoja_conectar'));
final hojaDesconectar184 = find.byKey(const Key('drive_hoja_desconectar'));
final conectar184 = find.byKey(const Key('drive_conectar'));
final ahoraNo184 = find.byKey(const Key('drive_ahora_no'));
final desconectar184 = find.byKey(const Key('drive_desconectar'));
final cancelar184 = find.byKey(const Key('drive_desconectar_cancelar'));
final avisoRevocado184 = find.byKey(const Key('configuracion_drive_aviso_revocado'));
final avisoCancelado184 = find.byKey(const Key('configuracion_drive_aviso_cancelado'));
final accionAviso184 = find.byKey(const Key('aviso_drive_accion'));

/// Lo que el test necesita de la pantalla montada.
final class Montaje184 {
  Montaje184({required this.drive, required this.container, required this.compuerta});

  final RespaldoDriveArmado drive;
  final ProviderContainer container;

  /// La compuerta de Google si el estado la deja cerrada (`conectando`, `cargando`).
  final Completer<void>? compuerta;
}

/// Lleva la fila al medio de la pantalla, como la deja una persona que baja hasta «Respaldo».
Future<void> verFila184(WidgetTester tester) async {
  await tester.scrollUntilVisible(fila184, 200, scrollable: find.byType(Scrollable).first);
  await Scrollable.ensureVisible(tester.element(fila184), alignment: 0.4);
  await tester.pumpAndSettle();
}

Future<void> tocarFila184(WidgetTester tester) async {
  await verFila184(tester);
  await tester.tap(fila184);
  await tester.pumpAndSettle();
}

/// Baja la hoja hasta el final, como quien lee todo antes de tocar el botón.
Future<void> bajarHoja184(WidgetTester tester, Finder hoja) async {
  final scroll = find.descendant(of: hoja, matching: find.byType(Scrollable));
  if (scroll.evaluate().isEmpty) return;
  await tester.drag(scroll.first, const Offset(0, -4000));
  await tester.pumpAndSettle();
}

Future<void> tocar184(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Monta la app y deja Configuración en [estado]. [email] cambia el correo de la cuenta de Google.
Future<Montaje184> montar184(
  WidgetTester tester,
  Estado184 estado, {
  Size tamano = chico184,
  double escala = 1,
  String? email,
  RespaldoDriveArmado? armado,
}) async {
  await cargarFuentes408(tester);
  final drive = armado ?? RespaldoDriveArmado();
  if (email != null) drive.google.cuenta = CuentaGoogle(id: 'g-100', email: email);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final container = ProviderContainer(
    overrides: [
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(
        AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      respaldoDriveRepositoryProvider.overrideWithValue(drive.repo),
      if (estado == Estado184.sinConexion)
        conexionProvider.overrideWith((ref) => Stream.value(TipoConexion.sinConexion)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  await container
      .read(sesionProvider.notifier)
      .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
  final usuarioId = container.read(sesionProvider).value!.usuarioId;

  // Lo que ya estaba guardado antes de abrir Configuración.
  switch (estado) {
    case Estado184.desconectar || Estado184.errorDesconectar:
      await drive.repo.conectar(usuarioId);
    case Estado184.revocado:
      await drive.repo.conectar(usuarioId);
      await drive.repo.marcarPermisoRevocado(usuarioId);
    case Estado184.sinEspacio:
      await drive.repo.conectar(usuarioId);
      await drive.repo.marcarSinEspacio(usuarioId);
    default:
      break;
  }
  Completer<void>? compuerta;
  if (estado == Estado184.cargando) {
    compuerta = Completer<void>();
    drive.almacen.compuertaLeer = compuerta;
  }
  if (estado == Estado184.errorLectura) drive.almacen.alLeer = true;
  if (estado == Estado184.conectando) {
    compuerta = Completer<void>();
    drive.google.compuertaConectar = compuerta;
  }
  if (estado == Estado184.cancelo) {
    drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.canceled);
  }
  if (estado == Estado184.error) {
    drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.unknownError);
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ColportoresApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('inicio_configuracion')));
  if (estado == Estado184.cargando) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(
      find.text('Revisando tu respaldo…'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    return Montaje184(drive: drive, container: container, compuerta: compuerta);
  }
  await tester.pumpAndSettle();

  switch (estado) {
    case Estado184.sinConectar || Estado184.revocado || Estado184.sinEspacio:
      await verFila184(tester);
    case Estado184.errorLectura:
      await verFila184(tester);
    case Estado184.previa || Estado184.sinConexion:
      await tocarFila184(tester);
    case Estado184.conectando:
      await tocarFila184(tester);
      await tester.ensureVisible(conectar184);
      await tester.pump();
      await tester.tap(conectar184);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    case Estado184.conectada:
      await tocarFila184(tester);
      await tocar184(tester, conectar184);
    case Estado184.cancelo:
      await tocarFila184(tester);
      await tocar184(tester, conectar184);
    case Estado184.error:
      await tocarFila184(tester);
      await bajarHoja184(tester, hojaConectar184);
      await tocar184(tester, conectar184);
    case Estado184.desconectar:
      await tocarFila184(tester);
    case Estado184.errorDesconectar:
      await tocarFila184(tester);
      await bajarHoja184(tester, hojaDesconectar184);
      drive.almacen.alBorrar = true;
      await tocar184(tester, desconectar184);
    case Estado184.cargando:
      break;
  }
  return Montaje184(drive: drive, container: container, compuerta: compuerta);
}

/// La pantalla completa (incluidas las hojas y los avisos) como PNG, solo con `QA_CAPTURAS`.
Future<void> capturar184(WidgetTester tester, String nombre) async {
  if (!conCapturas184) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/184_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

bool get conCapturas184 => conCapturas408;

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado184(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// El widget está del todo dentro de la pantalla.
bool enPantalla184(WidgetTester tester, Finder f) {
  final r = tester.getRect(f);
  final v = tester.view.physicalSize / tester.view.devicePixelRatio;
  return r.top >= 0 && r.left >= 0 && r.bottom <= v.height && r.right <= v.width;
}

/// Qué ve la persona en cada estado: los textos del canvas (o de la HU) que tienen que estar.
List<String> textosDe184(Estado184 e) => switch (e) {
  Estado184.sinConectar => ['Cuenta Drive', 'Sin conectar · tus datos no tienen respaldo'],
  Estado184.previa => [
    'Respaldo en tu Google Drive',
    'Guardamos una copia de tus datos en una carpeta oculta de tu Drive. Los archivos van cifrados, '
        'Google no los puede leer, y solo esta app los puede acceder.',
    'Se respalda cada noche. Podés desconectarlo cuando quieras.',
    'Conectar con Google',
    'Ahora no',
  ],
  Estado184.conectando => ['Conectando…'],
  Estado184.conectada => ['ana.gomez@gmail.com', 'Backup configurado. Próximo backup nocturno.'],
  Estado184.desconectar => [
    '¿Desconectar Google Drive?',
    'Los respaldos dejan de hacerse. Las copias que ya están en tu Drive no se borran: si '
        'querés, las borrás desde Drive.',
    'Desconectar',
    'Cancelar',
  ],
  Estado184.revocado => [
    'Google ya no nos deja guardar tu respaldo. Volvé a conectar tu Drive para no perder datos.',
    'Sin permiso · los respaldos están frenados',
  ],
  Estado184.cancelo => [
    'No conectamos tu Drive. Podés hacerlo cuando quieras.',
    'Sin conectar · tus datos no tienen respaldo',
  ],
  Estado184.sinConexion => [
    'Necesitás conexión para conectar Google Drive.',
    'Conectar con Google',
  ],
  Estado184.error => ['No pudimos conectar tu Drive. Probá de nuevo.', 'Reintentar', 'Ahora no'],
  Estado184.sinEspacio => ['Tu Drive está lleno · el respaldo no se guardó'],
  Estado184.cargando => ['Revisando tu respaldo…'],
  Estado184.errorLectura => ['No pudimos ver el estado de tu respaldo.', 'Reintentar'],
  Estado184.errorDesconectar => [
    'No pudimos desconectar tu Drive. Probá de nuevo.',
    'Reintentar',
    'Cancelar',
  ],
};
