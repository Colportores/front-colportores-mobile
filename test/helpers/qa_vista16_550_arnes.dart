// Arnés del QA de la vista 16, artboards 16E (otra cuenta de Google) y 16F (franja del Drive en Hoy),
// #550: la app entera con el respaldo en Drive armado sobre el almacén en memoria, en los estados del
// canvas y en los que el canvas no dibuja.
//
// Capturas PNG con `--dart-define=QA_CAPTURAS=true`, en `.dart_tool/qa_capturas/` (gitignored).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/permiso_notificaciones_repository.dart';
import 'package:colportores_mobile/features/respaldo/data/services/servicio_google.dart'
    show CuentaGoogle;
import 'package:colportores_mobile/features/respaldo/domain/repositories/respaldo_drive_repository.dart'
    show PrimerRespaldoDrive;
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'db_local_repository_en_memoria.dart';
import 'notificaciones_arnes.dart' show Telefono;
import 'respaldo_drive_falsos.dart';

const conCapturas = bool.fromEnvironment('QA_CAPTURAS');

/// Los tamaños de la matriz: (nombre, ancho, alto, escala de texto).
const tamanos550 = <(String, double, double, double)>[
  ('360x640_1x', 360, 640, 1),
  ('360x640_2x', 360, 640, 2),
  ('412x915_1x', 412, 915, 1),
  ('412x915_2x', 412, 915, 2),
];

const cuentaNueva550 = CuentaGoogle(id: 'g-200', email: 'lu.silva.casa@gmail.com');
const correoAnterior550 = 'ana.gomez@gmail.com';

final hojaOtra = find.byKey(const Key('drive_hoja_otra_cuenta'));
final hojaSeguir = find.byKey(const Key('drive_hoja_seguir_con_la_nueva'));
final botonVolver = find.byKey(const Key('drive_otra_cuenta_volver'));
final botonSeguir = find.byKey(const Key('drive_otra_cuenta_seguir'));
final botonConfirmarSeguir = find.byKey(const Key('drive_otra_cuenta_confirmar_seguir'));
final botonConfirmarVolver = find.byKey(const Key('drive_otra_cuenta_confirmar_volver'));
final avisoErrorHoja = find.byKey(const Key('drive_hoja_otra_cuenta_error'));
final avisoSinConexionHoja = find.byKey(const Key('drive_hoja_otra_cuenta_sin_conexion'));
final filaDrive = find.byKey(const Key('configuracion_drive_fila'));
final engranaje = find.byKey(const Key('inicio_configuracion'));
final marcaEngranaje = find.byKey(const Key('inicio_configuracion_marca'));
final franjaRevocada = find.byKey(const Key('aviso_drive_en_hoy_permisoRevocado'));
final franjaLlena = find.byKey(const Key('aviso_drive_en_hoy_sinEspacio'));
final botonOcultar = find.byKey(const Key('aviso_drive_accion_secundaria'));
final botonAccionFranja = find.byKey(const Key('aviso_drive_accion'));
final avisoDeLaFranja = find.byKey(const Key('inicio_franja_avisos'));

/// Lo que arma el test antes de abrir la app.
class Mundo550 {
  Mundo550({DateTime? ahora, PrimerRespaldoDrive? primerRespaldo})
    : ahora = ahora ?? DateTime(2026, 11, 20, 22, 30) {
    drive = RespaldoDriveArmado(primerRespaldo: primerRespaldo, ahora: () => this.ahora);
  }

  DateTime ahora;
  late final RespaldoDriveArmado drive;
  late ProviderContainer container;

  /// Ana tenía su respaldo en la cuenta de siempre y Google ya le devolvió otra: queda por confirmar.
  Future<void> porConfirmar(String u) async {
    await drive.repo.conectar(u);
    drive.google.cuenta = cuentaNueva550;
    await drive.repo.conectar(u);
  }

  Future<void> revocado(String u) async {
    await drive.repo.conectar(u);
    await drive.repo.marcarPermisoRevocado(u);
  }

  Future<void> lleno(String u) async {
    await drive.repo.conectar(u);
    await drive.repo.marcarSinEspacio(u);
  }
}

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

/// La app entera en Hoy, con el respaldo en el estado que arme [antes].
Future<ProviderContainer> montar550(
  WidgetTester tester,
  Mundo550 mundo, {
  Future<void> Function(String usuarioId)? antes,
  TipoConexion? conexion,
  double ancho = 390,
  double alto = 844,
  double escala = 1,
  bool fuentesReales = false,
  Telefono? telefono,
  DateTime Function()? ultimo,
}) async {
  if (fuentesReales) await cargarFuentesReales(tester);
  tester.view.physicalSize = Size(ancho, alto);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final container = ProviderContainer(
    overrides: [
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(
        AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      respaldoDriveRepositoryProvider.overrideWithValue(mundo.drive.repo),
      relojRespaldoDriveProvider.overrideWithValue(() => mundo.ahora),
      if (conexion != null) conexionProvider.overrideWith((ref) => Stream.value(conexion)),
      if (ultimo != null) ultimoRespaldoDriveProvider.overrideWith((ref) => Stream.value(ultimo())),
      if (telefono != null) ...telefono.overrides,
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  await container
      .read(sesionProvider.notifier)
      .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
  final usuarioId = container.read(sesionProvider).value!.usuarioId;
  await antes?.call(usuarioId);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ColportoresApp()),
  );
  await tester.pumpAndSettle();
  mundo.container = container;
  return container;
}

Future<void> irAConfiguracion550(WidgetTester tester) async {
  await tester.tap(engranaje);
  await tester.pumpAndSettle();
}

/// Toca [f] llevándolo antes a la vista (en la hoja a 2× está bajo el pliegue).
Future<void> tocar550(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> tocarFila550(WidgetTester tester) async {
  await tester.scrollUntilVisible(filaDrive, 200, scrollable: find.byType(Scrollable).first);
  await Scrollable.ensureVisible(tester.element(filaDrive), alignment: 0.4);
  await tester.pumpAndSettle();
  await tester.tap(filaDrive);
  await tester.pumpAndSettle();
}

/// Los estados que se miran en la matriz (tamaño × texto) y en las capturas.
enum Estado550 {
  filaPendiente('16E·01 fila ámbar en Configuración'),
  hoja01('16E·01 hoja Esta no es la cuenta'),
  hoja02('16E·02 hoja Seguir con la nueva'),
  hoja04('16E·04 sin conexión'),
  hojaError('16E·01 con aviso de error al volver'),
  hojaCorreoLargo('16E·01 con correos largos'),
  volvio03('16E·03 Volvió a la anterior, aviso'),
  hoy01('16F·01 Hoy permiso revocado'),
  hoy02('16F·02 Hoy Drive lleno'),
  hoy03('16F·03 Hoy con otros avisos'),
  hoy04('16F·04 Hoy oculta hasta mañana'),
  hoy05('R7 Hoy con otra cuenta por confirmar');

  const Estado550(this.rotulo);
  final String rotulo;

  bool get esHoja => switch (this) {
    hoja01 || hoja02 || hoja04 || hojaError || hojaCorreoLargo => true,
    _ => false,
  };
}

const correoLargo550 = 'colportora.de.la.zona.cerro.norte.primavera.dos.mil.veintiseis@gmail.com';

/// Monta la app y la deja en [estado].
Future<Mundo550> armarEstado550(
  WidgetTester tester,
  Estado550 estado, {
  double ancho = 390,
  double alto = 844,
  double escala = 1,
  bool fuentesReales = false,
}) async {
  final mundo = Mundo550();
  Future<void> Function(String)? antes;
  TipoConexion? conexion;
  Telefono? telefono;
  switch (estado) {
    case Estado550.hoy05 ||
        Estado550.filaPendiente ||
        Estado550.hoja01 ||
        Estado550.hoja02 ||
        Estado550.hojaError ||
        Estado550.volvio03:
      antes = mundo.porConfirmar;
    case Estado550.hoja04:
      antes = mundo.porConfirmar;
      conexion = TipoConexion.sinConexion;
    case Estado550.hojaCorreoLargo:
      antes = (u) async {
        await mundo.drive.repo.conectar(u);
        mundo.drive.google.cuenta = const CuentaGoogle(id: 'g-999', email: correoLargo550);
        await mundo.drive.repo.conectar(u);
      };
    case Estado550.hoy01 || Estado550.hoy04:
      antes = mundo.revocado;
    case Estado550.hoy02:
      antes = mundo.lleno;
    case Estado550.hoy03:
      antes = mundo.revocado;
      telefono = Telefono()..recuerdo.pedido = PedidoNotificaciones.ahoraNo;
  }
  await montar550(
    tester,
    mundo,
    antes: antes,
    conexion: conexion,
    ancho: ancho,
    alto: alto,
    escala: escala,
    fuentesReales: fuentesReales,
    telefono: telefono,
    ultimo: () => DateTime(2026, 10, 20, 3, 10),
  );
  switch (estado) {
    case Estado550.hoy01 || Estado550.hoy02 || Estado550.hoy03 || Estado550.hoy05:
      break;
    case Estado550.hoy04:
      await tocar550(tester, botonOcultar);
    case Estado550.filaPendiente:
      await irAConfiguracion550(tester);
      await tester.scrollUntilVisible(filaDrive, 200, scrollable: find.byType(Scrollable).first);
      await Scrollable.ensureVisible(tester.element(filaDrive), alignment: 0.4);
      await tester.pumpAndSettle();
    case Estado550.hoja01 || Estado550.hoja04 || Estado550.hojaCorreoLargo:
      await irAConfiguracion550(tester);
      await tocarFila550(tester);
    case Estado550.hoja02:
      await irAConfiguracion550(tester);
      await tocarFila550(tester);
      await tocar550(tester, botonSeguir);
    case Estado550.hojaError:
      await irAConfiguracion550(tester);
      await tocarFila550(tester);
      mundo.drive.google.errorAlConectar = StateError('Google falló');
      await tocar550(tester, botonVolver);
    case Estado550.volvio03:
      await irAConfiguracion550(tester);
      await tocarFila550(tester);
      mundo.drive.google.cuenta = cuentaDeAna;
      await tocar550(tester, botonVolver);
  }
  return mundo;
}

/// Una captura PNG de toda la vista (incluye las hojas modales) en
/// `.dart_tool/qa_capturas/550_<nombre>.png`. El nombre sin `:` ni `·`.
Future<void> capturar550(WidgetTester tester, String nombre) async {
  if (!conCapturas) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/550_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
