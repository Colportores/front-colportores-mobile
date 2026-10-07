// Arnés de los tests de QA de las vistas de acceso (login y registro, #265): monta `LoginPage` o
// `RegistroPage` con el remoto en memoria y deja fijar tamaño, texto y teclado.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/data/repositories/ultimo_correo_repository_impl.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/reingreso_sesion_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'db_local_repository_en_memoria.dart';
import 'remoto_sin_sesion_deslizante.dart';

/// Los tres teléfonos de la QA móvil: el chico, el del diseño y el grande.
const tamanosAcceso = [Size(360, 640), Size(390, 844), Size(412, 915)];

/// Cuenta que existe en el remoto en memoria.
const correoAna = 'ana@example.com';
const claveAna = 'secreto123';

/// Fija el tamaño de la pantalla (1 px lógico = 1 px físico) y, si se pide, el teclado abierto.
void fijarPantalla(WidgetTester tester, Size tamano, {double teclado = 0}) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  if (teclado > 0) tester.view.viewInsets = FakeViewPadding(bottom: teclado);
  addTearDown(tester.view.reset);
  addTearDown(tester.view.resetViewInsets);
}

/// Sube el teclado (alto [alto]) con la pantalla ya montada y un campo con foco.
void abrirTeclado(WidgetTester tester, double alto) {
  tester.view.viewInsets = FakeViewPadding(bottom: alto);
  addTearDown(tester.view.resetViewInsets);
}

/// Remoto con el que se fuerza una falla (o una demora) en el inicio de sesión y el registro.
/// Sin [falla] delega en el remoto en memoria, así que un reintento puede entrar.
final class RemotoQueFalla with RemotoSinSesionDeslizante implements AuthRemoteDataSource {
  RemotoQueFalla([AuthRemoteDataSourceEnMemoria? interno])
    : interno = interno ?? AuthRemoteDataSourceEnMemoria(credenciales: const {correoAna: claveAna});

  final AuthRemoteDataSourceEnMemoria interno;

  /// Si no es `null`, `iniciarSesion` y `registrar` la lanzan (después de [demora]).
  AuthRemoteException? falla;

  /// Si no es `null`, las llamadas esperan a que el test lo complete: la acción queda «a mitad».
  Completer<void>? demora;

  int llamadasIniciarSesion = 0;
  int llamadasRegistrar = 0;

  @override
  Future<SesionModel> iniciarSesion({required String email, required String password}) async {
    llamadasIniciarSesion++;
    await demora?.future;
    if (falla case final f?) throw f;
    return interno.iniciarSesion(email: email, password: password);
  }

  @override
  Future<SesionModel?> registrar({
    required String nombre,
    required String apellido,
    required String cedula,
    required String email,
    required String password,
  }) async {
    llamadasRegistrar++;
    await demora?.future;
    if (falla case final f?) throw f;
    return interno.registrar(
      nombre: nombre,
      apellido: apellido,
      cedula: cedula,
      email: email,
      password: password,
    );
  }

  @override
  Future<SesionModel?> obtenerSesionActual() => interno.obtenerSesionActual();

  @override
  SesionModel? sesionEnElCliente() => interno.sesionEnElCliente();

  @override
  Future<void> cerrarSesion(String accessToken) => interno.cerrarSesion(accessToken);

  @override
  Future<void> revocarSesion(String accessToken) => interno.revocarSesion(accessToken);

  @override
  Future<void> reenviarVerificacion(String email) => interno.reenviarVerificacion(email);

  @override
  Stream<void> get erroresVerificacionEmail => interno.erroresVerificacionEmail;

  @override
  Stream<void> get verificacionesExitosas => interno.verificacionesExitosas;

  @override
  Future<void> solicitarRecuperacionPassword(String email) =>
      interno.solicitarRecuperacionPassword(email);
}

/// Un reingreso fijo («Sesión vencida», vista 17).
class ReingresoFijoQa extends ReingresoSesion {
  ReingresoFijoQa(this._datos);

  final DatosReingreso _datos;

  @override
  DatosReingreso? build() => _datos;
}

/// Monta [home] (la pantalla de acceso) con el remoto dado y el texto a [escala].
///
/// El `ProviderScope` va como argumento directo de `pumpWidget` (riverpod_lint).
Future<void> montarAcceso(
  WidgetTester tester, {
  required Widget home,
  AuthRemoteDataSource? remoto,
  double escala = 1,
  DatosReingreso? reingreso,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(
        remoto ?? AuthRemoteDataSourceEnMemoria(credenciales: const {correoAna: claveAna}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      ultimoCorreoRepositoryProvider.overrideWithValue(UltimoCorreoEnMemoria()),
      if (reingreso != null) reingresoSesionProvider.overrideWith(() => ReingresoFijoQa(reingreso)),
    ],
    child: MaterialApp(
      theme: temaClaro(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: child!,
      ),
      home: home,
    ),
  ),
);

/// Las cuatro guías de accesibilidad de Flutter sobre lo que hay en pantalla.
Future<void> guiasDeAccesibilidad(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}
