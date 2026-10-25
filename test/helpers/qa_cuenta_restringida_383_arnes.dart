// Arnés de la QA de la respuesta tardía que restringe la cuenta (#383): monta la app completa con
// los fakes en memoria, entra con lo último que sabía («activa») y deja la consulta colgada.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/asignacion_campania_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/estado_cuenta_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/asignacion_campania_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'alta_ubicacion_falsos.dart';
import 'alta_ubicacion_qa_arnes.dart';
import 'db_local_repository_en_memoria.dart';

final principal = find.byKey(const Key('inicio_principal'));
final titulo = find.byKey(const Key('espera_titulo'));
final botonConfiguracion = find.byKey(const Key('inicio_configuracion'));
final atrasDeConfiguracion = find.byKey(const Key('configuracion_atras'));
final aviso = find.byKey(const Key('cuenta_restringida_aviso'));
final entendido = find.byKey(const Key('cuenta_restringida_entendido'));
final botonLogin = find.byKey(const Key('login_enviar'));

const topeDelArranque = Duration(seconds: 15);

/// Los literales de la HU-AUTH-008 (criterio «Edge - cuenta SUSPENDIDA después de estar ACTIVA»).
const literalSuspendida = 'Tu cuenta está suspendida. Contactá al administrador.';

late EstadoCuentaEnMemoria backend;
late EstadoCuentaLocalEnMemoria recordado;
late ProviderContainer contenedor;
late RepoAltaFalso repo;

Future<void> montar(WidgetTester tester, {required EstadoCuenta contestara}) async {
  backend = EstadoCuentaEnMemoria(estado: contestara);
  recordado = EstadoCuentaLocalEnMemoria();
  repo = RepoAltaFalso();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        ahoraEsperaProvider.overrideWithValue(() => DateTime(2026, 10, 7, 14, 30)),
        asignacionCampaniaDataSourceProvider.overrideWithValue(AsignacionCampaniaEnMemoria()),
        estadoCuentaRemoteDataSourceProvider.overrideWithValue(backend),
        estadoCuentaLocalDataSourceProvider.overrideWithValue(recordado),
        ...overridesAlta(repo: repo),
      ],
      child: const ColportoresApp(),
    ),
  );
  await tester.pumpAndSettle();
  contenedor = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

Future<void> entrar(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
  await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
  await tester.ensureVisible(botonLogin);
  await tester.tap(botonLogin);
  await tester.pump();
  await tester.pump();
}

Future<void> vencerElTope(WidgetTester tester) async {
  await tester.pump(topeDelArranque);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

void fijarTamano(WidgetTester tester, Size tam, {double texto = 1}) {
  tester.view
    ..physicalSize = tam
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<Completer<void>> enElInicio(WidgetTester tester, {required EstadoCuenta contestara}) async {
  await montar(tester, contestara: contestara);
  final colgada = backend.demora = Completer<void>();
  await entrar(tester);
  final usuarioId = contenedor.read(sesionProvider).value!.usuarioId;
  await recordado.guardar(usuarioId, EstadoCuenta.activa);
  await vencerElTope(tester);
  expect(principal, findsOneWidget);
  return colgada;
}

Future<void> llegaLaRespuesta(WidgetTester tester, Completer<void> colgada) async {
  colgada.complete();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> abrirElAlta(WidgetTester tester) async {
  final usuarioId = contenedor.read(sesionProvider).value!.usuarioId;
  unawaited(AltaUbicacionPage.abrir(tester.element(principal), colportorId: usuarioId));
  await asentar(tester);
  await tocar(tester, find.text('Casa'));
  expect(botonRegistrar, findsOneWidget);
}

Future<void> abrirConfiguracion(WidgetTester tester) async {
  await tester.tap(botonConfiguracion);
  await tester.pumpAndSettle();
  expect(atrasDeConfiguracion, findsOneWidget);
}
