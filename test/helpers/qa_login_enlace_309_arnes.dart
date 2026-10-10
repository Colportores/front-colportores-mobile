// Arnés de la QA de #309 (PR #341, login: el enlace de recuperación y «Registrate» con «Entrar» en
// vuelo): monta la app entera en el login (1a/1b) o en una de las pantallas de la vista 17, deja el
// intento «a mitad» y mide dónde cae el foco. Lo usan `qa_login_enlace_309_test.dart` (guías de
// accesibilidad y cruces) y `qa_login_enlace_309_medidas_test.dart` (tipografía real).
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/domain/entities/motivo_expiracion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/acceso_qa_arnes.dart';
import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/tiles_falsos.dart';

const llaveRecuperar = Key('login_olvidaste_clave');
const llaveEntrar = Key('login_enviar');
const llaveCorreo = Key('login_email');
const llaveClave = Key('login_password');
const llaveRegistro = Key('login_ir_a_registro');
const llaveCerrarAviso = Key('login_aviso_sesion_cerrar');
const llaveInicio = Key('inicio_principal');

const textoRegistro = '¿No tenés cuenta? Registrate';

/// Las pantallas del login (17-A02 no dibuja el enlace de recuperación).
enum PantallaLogin {
  inicial('1a/1b · inicial', '¿Olvidaste tu clave?'),
  a01('17-A01 · expiró por inactividad', 'Recuperar acceso'),
  a02('17-A02 · vencida y sin conexión', null),
  a03('17-A03 · revocada por el servidor', 'Recuperar acceso'),
  a04('17-A04 · aviso descartado', 'Recuperar acceso');

  const PantallaLogin(this.nombre, this.enlace);

  final String nombre;
  final String? enlace;
}

/// Las que dibujan el enlace de recuperación.
final pantallasConEnlace = PantallaLogin.values.where((p) => p.enlace != null).toList();

SesionModel sesionDeLucia() => SesionModel(
  usuarioId: '01920000-0000-7000-8000-000000000001',
  email: 'lucia.silva@correo.com',
  accessToken: 'jwt',
  expiraEn: DateTime.now().toUtc().add(const Duration(days: 29)),
);

class EntornoLogin {
  EntornoLogin(this.remoto, this.local, this.conexion);

  final AuthRemoteDataSourceEnMemoria remoto;
  final AuthLocalDataSourceEnMemoria local;
  final ConectividadFalsa conexion;
}

/// Carga Inter, Source Serif 4, JetBrains Mono y los íconos de Material: sin ellas `flutter_test`
/// pinta cada letra como un cuadrado y las medidas de texto no son las de un teléfono.
Future<void> cargarFuentesReales(WidgetTester tester) => tester.runAsync(() async {
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

/// La app entera con la tipografía real. El remoto en memoria acepta a Ana y a Lucía.
Future<EntornoLogin> montarAppLogin(
  WidgetTester tester, {
  AuthLocalDataSourceEnMemoria? local,
  TipoConexion tipo = TipoConexion.wifi,
  bool fuentesReales = false,
}) async {
  if (fuentesReales) await cargarFuentesReales(tester);
  final entorno = EntornoLogin(
    AuthRemoteDataSourceEnMemoria(
      credenciales: const {correoAna: claveAna, 'lucia.silva@correo.com': 'Secreto123'},
    ),
    local ?? AuthLocalDataSourceEnMemoria(),
    ConectividadFalsa()..tipo = tipo,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(entorno.remoto),
        authLocalDataSourceProvider.overrideWithValue(entorno.local),
        monitorConectividadProvider.overrideWithValue(entorno.conexion),
      ],
      child: const ColportoresApp(),
    ),
  );
  await tester.pumpAndSettle();
  return entorno;
}

void fijarPantallaLogin(WidgetTester tester, Size tam, {double texto = 1, double teclado = 0}) {
  tester.view
    ..physicalSize = tam
    ..devicePixelRatio = 1;
  if (teclado > 0) tester.view.viewInsets = FakeViewPadding(bottom: teclado);
  addTearDown(tester.view.reset);
  addTearDown(tester.view.resetViewInsets);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Lleva la app a [pantalla]: la inicial sin sesión; A01 y A03 con la sesión de Lucía que vence
/// (por inactividad o revocada); A04 es A01 con el aviso cerrado.
Future<EntornoLogin> llegarALogin(
  WidgetTester tester,
  PantallaLogin pantalla, {
  TipoConexion tipo = TipoConexion.wifi,
  bool fuentesReales = false,
}) async {
  if (pantalla == PantallaLogin.inicial) {
    return montarAppLogin(tester, tipo: tipo, fuentesReales: fuentesReales);
  }
  final local = AuthLocalDataSourceEnMemoria();
  await local.guardarSesion(sesionDeLucia());
  final e = await montarAppLogin(tester, local: local, tipo: tipo, fuentesReales: fuentesReales);
  e.remoto.simularExpiracion(
    pantalla == PantallaLogin.a03 ? MotivoExpiracion.revocada : MotivoExpiracion.inactividad,
  );
  await tester.pumpAndSettle();
  if (pantalla == PantallaLogin.a04) {
    await tester.tap(find.byKey(llaveCerrarAviso));
    await tester.pumpAndSettle();
  }
  return e;
}

/// Escribe una contraseña que el servidor rechaza (en la vista 17 el correo ya viene puesto).
Future<void> escribirEnLogin(
  WidgetTester tester,
  PantallaLogin pantalla, {
  String clave = 'incorrecta1',
}) async {
  if (pantalla == PantallaLogin.inicial) await tester.enterText(find.byKey(llaveCorreo), correoAna);
  await tester.enterText(find.byKey(llaveClave), clave);
}

/// Toca «Entrar» y deja el intento a mitad: el servidor contesta cuando el test completa la demora.
Future<Completer<void>> dejarEnVuelo(
  WidgetTester tester,
  EntornoLogin e,
  PantallaLogin pantalla, {
  String? clave,
}) async {
  final demora = Completer<void>();
  e.remoto.demoraIniciarSesion = demora;
  await escribirEnLogin(tester, pantalla, clave: clave ?? 'incorrecta1');
  await tester.ensureVisible(find.byKey(llaveEntrar));
  await tester.tap(find.byKey(llaveEntrar));
  await tester.pump();
  return demora;
}

Future<void> guiasLogin(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  expect(tester.takeException(), isNull);
}

bool estaApagado(WidgetTester tester, Key llave) =>
    tester.widget<TextButton>(find.byKey(llave)).onPressed == null;

/// Dónde está el foco del teclado, en el vocabulario del login.
String? dondeEstaElFoco(WidgetTester tester) {
  final contexto = FocusManager.instance.primaryFocus?.context;
  if (contexto == null) return null;
  bool dentroDe(Finder f) {
    if (f.evaluate().isEmpty) return false;
    final objetivo = tester.element(f.first);
    if (contexto == objetivo) return true;
    var halla = false;
    contexto.visitAncestorElements((a) {
      if (a == objetivo) halla = true;
      return !halla;
    });
    return halla;
  }

  if (dentroDe(find.byTooltip('Cerrar aviso'))) return 'cerrar aviso';
  if (dentroDe(find.byTooltip('Mostrar contraseña'))) return 'ojo';
  if (dentroDe(find.byKey(llaveCorreo))) return 'correo';
  if (dentroDe(find.byKey(llaveClave))) return 'contraseña';
  if (dentroDe(find.byKey(llaveRecuperar))) return 'recuperar';
  if (dentroDe(find.byKey(llaveEntrar))) return 'entrar';
  if (dentroDe(find.byKey(llaveRegistro))) return 'registro';
  return 'otro';
}

Future<List<String?>> tabularLogin(WidgetTester tester, int veces) async {
  final visitados = <String?>[];
  for (var i = 0; i < veces; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    visitados.add(dondeEstaElFoco(tester));
  }
  return visitados;
}
