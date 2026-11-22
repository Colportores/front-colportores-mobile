// Arnés del QA del asistente de recuperación (vista 34, HU-SYNC-006, #175): lleva la pantalla a cada
// estado del canvas (34·01 a 34·10) y a los que el canvas no dibuja, en cualquier tamaño y con
// cualquier escala de texto. Las capturas solo se sacan con `--dart-define=QA_CAPTURAS=true` y van a
// `.dart_tool/qa_capturas` (fuera de git). Reusa el arnés del implementador.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/respaldo/domain/repositories/recuperacion_resuelta_repository.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_recuperacion.dart';
import 'package:colportores_mobile/features/respaldo/presentation/pages/recuperacion_page.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/recuperacion_pendiente_providers.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/recuperacion_providers.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'qa_vista23_408_arnes.dart' show cargarFuentes408, conCapturas408, usarFuentesReales408;
import 'recuperacion_arnes.dart';
import 'respaldo_drive_falsos.dart';

export 'qa_vista23_408_arnes.dart' show conCapturas408, usarFuentesReales408;
export 'recuperacion_arnes.dart';

const chico175 = Size(360, 640);
const grande175 = Size(412, 915);

String sufijo175(Size t, double e) => '${t.width.toInt()}x${t.height.toInt()}_x$e';

/// Cada estado al que se puede llegar. `cNN` son los artboards del canvas.
enum Estado175 {
  buscando('Buscando (carga del paso 1)'),
  c01Encontrado('34·01 Encontrado'),
  c02Conectar('34·02 Conectar Drive'),
  c02ConAviso('34·02 Conectar, Google cancelado'),
  c03Contrasena('34·03 Contraseña'),
  c04Distinta('34·04 Contraseña distinta'),
  c05Restaurando('34·05 Restaurando'),
  c05Aplicando('34·05 Armando la copia (sin Cancelar)'),
  c06Esperando('34·06 Interrumpida (el motor retoma solo)'),
  c06Reintentar('34·06 Interrumpida (con Reintentar)'),
  c07Parcial('34·07 Parte dañada'),
  c07Detalle('34·07 Parte dañada, detalle abierto'),
  c07ReintentoFallido('34·07 Parte dañada, el «Reintentar» no pudo'),
  c08Listo('34·08 Listo'),
  c09SinRespaldo('34·09 Sin respaldo'),
  c10SinConexion('34·10 Sin conexión'),
  fallaBusqueda('Falla la búsqueda'),
  varios('Varios respaldos'),
  versionNueva('Versión más nueva'),
  versionNuevaComo('Versión más nueva, cómo actualizar'),
  sinLlave('Respaldo sin clave'),
  ilegible('Respaldo ilegible'),
  fallida('Recuperación fallida'),
  sinPermiso('Drive perdió el permiso a mitad');

  const Estado175(this.rotulo);
  final String rotulo;
}

Future<void> asentar175(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> tocar175(WidgetTester tester, Finder objetivo) async {
  await tester.ensureVisible(objetivo);
  await tester.tap(objetivo);
  await asentar175(tester);
}

/// 34·01 → 34·03: elige recuperar y escribe la contraseña.
Future<void> irAContrasena175(WidgetTester tester, {String contrasena = 'la-de-antes'}) async {
  await tocar175(tester, cta);
  await tester.enterText(campoContrasena, contrasena);
  await asentar175(tester);
}

/// 34·03 → resultado: abre la copia.
Future<void> abrirCopia175(WidgetTester tester, {String contrasena = 'la-de-antes'}) async {
  await irAContrasena175(tester, contrasena: contrasena);
  await tocar175(tester, cta);
}

bool botonApagado175(WidgetTester tester, Finder boton) =>
    tester.widget<ButtonStyleButton>(boton).onPressed == null;

/// Lleva el asistente a [estado]; devuelve el arnés para que el test lo siga manejando.
Future<ArnesRecuperacion> llegarA175(
  WidgetTester tester,
  Estado175 estado, {
  Size tamano = chico175,
  double escala = 1,
}) async {
  await cargarFuentes408(tester);
  final a = ArnesRecuperacion();
  final s = a.servicio;
  switch (estado) {
    case Estado175.buscando:
      s.compuertaBuscar = Completer<void>();
    case Estado175.c02Conectar || Estado175.c02ConAviso:
      s.busqueda = const DriveSinPermiso();
    case Estado175.c09SinRespaldo:
      s.busqueda = const SinRespaldoEnDrive();
    case Estado175.c10SinConexion:
      s.busqueda = const BusquedaSinConexion();
    case Estado175.fallaBusqueda:
      s.busqueda = const BusquedaFallida();
    case Estado175.varios:
      s.busqueda = VariosRespaldosEnDrive([respaldoDePrueba, respaldoDePrueba]);
    case Estado175.c04Distinta:
      s.resultado = const ContrasenaNoAbreElRespaldo();
    case Estado175.c05Restaurando || Estado175.c05Aplicando:
      s.frenarRecuperar = true;
      s.progresos = [
        if (estado == Estado175.c05Restaurando)
          const ProgresoRecuperacion(PasoRecuperacion.bajando, hechas: 12, total: 15)
        else
          const ProgresoRecuperacion(PasoRecuperacion.aplicando),
      ];
    case Estado175.c06Esperando:
      s.frenarRecuperar = true;
      s.progresos = const [
        ProgresoRecuperacion(
          PasoRecuperacion.bajando,
          hechas: 12,
          total: 15,
          esperandoConexion: true,
        ),
      ];
    case Estado175.c06Reintentar:
      s.resultado = const RecuperacionSinConexion(hechas: 12, total: 15);
    case Estado175.c07Parcial || Estado175.c07Detalle || Estado175.c07ReintentoFallido:
      s.resultado = RecuperacionHecha(
        informeDePrueba(parcial: true, restauradas: 13, fecha: DateTime(2026, 10, 21, 3, 10)),
      );
    case Estado175.versionNueva || Estado175.versionNuevaComo:
      s.resultado = const RespaldoDeVersionMasNueva(esquemaDelRespaldo: 30, esquemaDeLaApp: 24);
    case Estado175.sinLlave:
      s.resultado = const SinLlaveParaElRespaldo();
    case Estado175.ilegible:
      s.resultado = const RespaldoIlegible();
    case Estado175.fallida:
      s.resultado = const RecuperacionFallida();
    case Estado175.sinPermiso:
      s.resultado = const RecuperacionSinPermiso();
    case Estado175.c01Encontrado || Estado175.c03Contrasena || Estado175.c08Listo:
      break;
  }
  await abrirAsistente175(tester, a, tamano: tamano, escala: escala);

  switch (estado) {
    case Estado175.c10SinConexion:
      a.conexion.cambiarA(TipoConexion.sinConexion);
      await asentar175(tester);
    case Estado175.c02ConAviso:
      a.drive.google.errorAlConectar = falloDeGoogle(GoogleSignInExceptionCode.canceled);
      await tocar175(tester, cta);
    case Estado175.c03Contrasena:
      await irAContrasena175(tester);
    case Estado175.c04Distinta ||
        Estado175.c05Restaurando ||
        Estado175.c05Aplicando ||
        Estado175.c06Esperando ||
        Estado175.c06Reintentar ||
        Estado175.c07Parcial ||
        Estado175.c07Detalle ||
        Estado175.c07ReintentoFallido ||
        Estado175.versionNueva ||
        Estado175.versionNuevaComo ||
        Estado175.sinLlave ||
        Estado175.ilegible ||
        Estado175.fallida ||
        Estado175.sinPermiso ||
        Estado175.c08Listo:
      await abrirCopia175(tester);
      if (estado == Estado175.c06Reintentar) {
        // El motor terminó sin conexión y la conexión ya volvió: «Reintentar» está encendido.
        await asentar175(tester);
      }
      if (estado == Estado175.c07Detalle) await tocar175(tester, cta2);
      if (estado == Estado175.c07ReintentoFallido) {
        a.servicio.resultado = const RecuperacionFallida();
        await tocar175(tester, cta3);
      }
      if (estado == Estado175.versionNuevaComo) await tocar175(tester, cta);
    default:
      break;
  }
  // Deja terminar las animaciones cortas (el botón, el campo).
  await tester.pump(const Duration(milliseconds: 400));
  return a;
}

final cta3 = find.byKey(const Key('recuperacion_cta3'));

/// Suelta lo que dejó trabado el estado para que el test termine limpio.
Future<void> liberar175(WidgetTester tester, ArnesRecuperacion a) async {
  final c1 = a.servicio.compuertaBuscar;
  if (c1 != null && !c1.isCompleted) c1.complete();
  final c2 = a.servicio.compuertaRecuperar;
  if (c2 != null && !c2.isCompleted) c2.complete();
  await asentar175(tester);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}

/// La pantalla completa como PNG, solo con `QA_CAPTURAS`.
Future<void> capturar175(WidgetTester tester, String nombre) async {
  if (!conCapturas408) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/175_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado175(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    if (e.findAncestorWidgetOfExactType<InputDecorator>() != null) continue;
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// Las fuentes reales solo se apagan en el archivo de las guías de Flutter.
void sinFuentesReales175() => usarFuentesReales408 = false;

/// El asistente suelto sobre el arnés, **sin la salpicadura de tinta de Material**: en este Docker el
/// shader `ink_sparkle.frag` no se compila para los tests y el primer toque de cada proceso revienta
/// (le pasa también a los tests del implementador; en CI no). Lo demás del tema es el real.
Future<void> abrirAsistente175(
  WidgetTester tester,
  ArnesRecuperacion arnes, {
  RecuperacionResueltaRepository? resuelta,
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  fijarTelefono(tester, tamano: tamano, escala: escala);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        asistenteDeRecuperacionHabilitadoProvider.overrideWithValue(true),
        servicioRecuperacionProvider.overrideWithValue(arnes.servicio),
        lectorDeLoRecuperadoProvider.overrideWithValue(arnes.lector),
        recuperacionResueltaRepositoryProvider.overrideWithValue(resuelta ?? arnes.resuelta),
        respaldoDriveRepositoryProvider.overrideWithValue(arnes.drive.repo),
        monitorConectividadProvider.overrideWithValue(arnes.conexion),
        sesionProvider.overrideWith(() => SesionFijaParaRecuperacion(sesionDePrueba())),
      ],
      child: MaterialApp(
        theme: temaClaro().copyWith(splashFactory: NoSplash.splashFactory),
        home: const RecuperacionPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}
