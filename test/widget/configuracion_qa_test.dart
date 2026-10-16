// QA de la vista 16 «Configuración y cerrar sesión» (#225, HU-AUTH-006): matriz de tamaños y
// escalas de texto con las cuatro guías de accesibilidad en cada estado, y casos límite de la hoja
// de cierre que no cubre configuracion_page_test.dart.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resumen_datos_locales.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/datos_locales_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

final class _Datos implements DatosLocalesRepository {
  int pendientes = 0;
  Completer<void>? demoraResumen;
  final List<bool> borrados = [];

  @override
  Future<Either<Failure, ResumenDatosLocales>> resumen() async {
    await demoraResumen?.future;
    return Right(
      ResumenDatosLocales(
        personas: 0,
        visitas: 0,
        operacionesSinSincronizar: pendientes,
        hayBackupEnDrive: false,
      ),
    );
  }

  @override
  Future<Either<Failure, ResultadoBorradoDatosLocales>> borrar({
    required bool incluirBackupDrive,
    bool reintento = false,
  }) async {
    borrados.add(incluirBackupDrive);
    return const Right(ResultadoBorradoDatosLocales.completo);
  }
}

final class _Local implements AuthLocalDataSource {
  SesionModel? _sesion;
  bool fallar = false;
  Completer<void>? demora;
  int intentos = 0;

  @override
  Future<SesionModel?> leerSesion() async => _sesion;

  @override
  Future<void> guardarSesion(SesionModel sesion) async => _sesion = sesion;

  @override
  Future<void> borrarSesion() async {
    intentos++;
    await demora?.future;
    if (fallar) throw Exception('keystore');
    _sesion = null;
  }
}

late AuthRemoteDataSourceEnMemoria _remote;
late _Datos _datos;
late _Local _local;

Future<ProviderContainer> _montar(WidgetTester tester, {String email = 'ana@example.com'}) async {
  _remote = AuthRemoteDataSourceEnMemoria(credenciales: {email: 'secreto123'});
  final container = ProviderContainer(
    overrides: [
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(_remote),
      authLocalDataSourceProvider.overrideWithValue(_local),
      datosLocalesRepositoryProvider.overrideWithValue(_datos),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  await container.read(sesionProvider.notifier).iniciarSesion(email: email, password: 'secreto123');
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ColportoresApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('inicio_configuracion')));
  await tester.pumpAndSettle();
  return container;
}

void _pantalla(WidgetTester tester, Size tamanio, double escala) {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _toque(WidgetTester tester, String clave) async {
  final f = find.byKey(Key(clave));
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  setUp(() {
    _datos = _Datos();
    _local = _Local();
  });

  const tamanios = {'360x640': Size(360, 640), '412x915': Size(412, 915)};
  const escalas = [1.0, 2.0];

  group('QA vista 16: tamaños, escalas y guías en cada estado', () {
    for (final MapEntry(key: nombre, value: tam) in tamanios.entries) {
      for (final escala in escalas) {
        final sufijo = '$nombre, texto ${escala}x';

        testWidgets('A01 principal ($sufijo): sin overflow y cumple las guías', (tester) async {
          final handle = tester.ensureSemantics();
          _pantalla(tester, tam, escala);
          await _montar(tester);
          expect(tester.takeException(), isNull);
          await _guias(tester);
          handle.dispose();
        });

        testWidgets('A02 sin pendientes ($sufijo): sin overflow y cumple las guías', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          _pantalla(tester, tam, escala);
          await _montar(tester);
          await _toque(tester, 'configuracion_cerrar_sesion');
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('configuracion_todo_sincronizado')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _guias(tester);
          handle.dispose();
        });

        testWidgets('A03 con pendientes ($sufijo): sin overflow y cumple las guías', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          _pantalla(tester, tam, escala);
          _datos.pendientes = 3;
          await _montar(tester);
          await _toque(tester, 'configuracion_cerrar_sesion');
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('configuracion_aviso_pendientes')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _guias(tester);
          handle.dispose();
        });

        testWidgets('A04 cerrando ($sufijo): sin overflow y cumple las guías', (tester) async {
          final handle = tester.ensureSemantics();
          _pantalla(tester, tam, escala);
          _local.demora = Completer<void>();
          await _montar(tester);
          await _toque(tester, 'configuracion_cerrar_sesion');
          await tester.pumpAndSettle();
          await _toque(tester, 'configuracion_dialogo_confirmar');
          expect(find.text('Cerrando sesión'), findsWidgets);
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
          _local.demora!.complete();
          await tester.pumpAndSettle();
        });

        testWidgets('A06 error ($sufijo): sin overflow y cumple las guías', (tester) async {
          final handle = tester.ensureSemantics();
          _pantalla(tester, tam, escala);
          _local.fallar = true;
          await _montar(tester);
          await _toque(tester, 'configuracion_cerrar_sesion');
          await tester.pumpAndSettle();
          await _toque(tester, 'configuracion_dialogo_confirmar');
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('configuracion_error_cierre')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _guias(tester);
          handle.dispose();
        });
      }
    }
  });

  group('QA vista 16: casos límite', () {
    testWidgets('el aviso de error se anuncia (liveRegion) y deja «Reintentar» a mano', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      _pantalla(tester, const Size(390, 844), 1);
      _local.fallar = true;
      await _montar(tester);
      await _toque(tester, 'configuracion_cerrar_sesion');
      await tester.pumpAndSettle();
      await _toque(tester, 'configuracion_dialogo_confirmar');
      await tester.pumpAndSettle();

      final aviso = find.ancestor(
        of: find.text('No pudimos cerrar la sesión. Probá de nuevo.'),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true),
      );
      expect(aviso, findsOneWidget);
      final sem = tester.getSemantics(find.byKey(const Key('configuracion_reintentar')));
      expect(sem.label, 'Reintentar');
      expect(sem.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('el atrás del sistema durante «Cerrando sesión» no cierra la hoja', (tester) async {
      _pantalla(tester, const Size(390, 844), 1);
      _local.demora = Completer<void>();
      await _montar(tester);
      await _toque(tester, 'configuracion_cerrar_sesion');
      await tester.pumpAndSettle();
      await _toque(tester, 'configuracion_dialogo_confirmar');

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(const Key('configuracion_dialogo_cierre')), findsOneWidget);
      expect(_local.intentos, 1);

      _local.demora!.complete();
      await tester.pumpAndSettle();
      expect(_login, findsOneWidget);
    });

    testWidgets(
      'con el error a la vista, tocar fuera de la hoja la cierra y el botón sigue activo',
      (tester) async {
        _pantalla(tester, const Size(390, 844), 1);
        _local.fallar = true;
        await _montar(tester);
        await _toque(tester, 'configuracion_cerrar_sesion');
        await tester.pumpAndSettle();
        await _toque(tester, 'configuracion_dialogo_confirmar');
        await tester.pumpAndSettle();

        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('configuracion_dialogo_cierre')), findsNothing);
        final boton = tester.widget<OutlinedButton>(
          find.byKey(const Key('configuracion_cerrar_sesion')),
        );
        expect(boton.onPressed, isNotNull);
        expect(_datos.borrados, isEmpty);
      },
    );

    testWidgets('volver mientras se cuentan las pendientes: al terminar no abre la hoja ni falla', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844), 1);
      _datos.demoraResumen = Completer<void>();
      await _montar(tester);
      await tester.tap(find.byKey(const Key('configuracion_cerrar_sesion')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('configuracion_atras')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('configuracion_pagina')), findsNothing);

      _datos.demoraResumen!.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('configuracion_dialogo_cierre')), findsNothing);
      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
    });

    testWidgets('con pendientes y sin red: «Cerrar sesión igual» lleva al login con el aviso', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844), 1);
      _datos.pendientes = 3;
      final container = await _montar(tester);
      _remote.simularSinConexion = true;
      await _toque(tester, 'configuracion_cerrar_sesion');
      await tester.pumpAndSettle();
      await _toque(tester, 'configuracion_dialogo_confirmar');
      await tester.pumpAndSettle();

      expect(_login, findsOneWidget);
      expect(find.byKey(const Key('login_aviso_sesion')), findsOneWidget);
      expect(container.read(sesionProvider).value, isNull);
      expect(_datos.borrados, isEmpty, reason: 'cerrar sesión nunca borra lo del teléfono');
    });

    testWidgets('tras un cierre sin red, volver a entrar descarta el aviso del login', (
      tester,
    ) async {
      _pantalla(tester, const Size(390, 844), 1);
      await _montar(tester);
      _remote.simularSinConexion = true;
      await _toque(tester, 'configuracion_cerrar_sesion');
      await tester.pumpAndSettle();
      await _toque(tester, 'configuracion_dialogo_confirmar');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login_aviso_sesion')), findsOneWidget);
      _remote.simularSinConexion = false;

      await tester.enterText(find.byType(TextField).first, 'ana@example.com');
      await tester.enterText(find.byType(TextField).at(1), 'secreto123');
      await tester.pump();
      await tester.tap(_login);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
      expect(find.byKey(const Key('login_aviso_sesion')), findsNothing);
    });

    testWidgets('correo larguísimo sin espacios a 360x640 y texto 2.0: sin overflow', (
      tester,
    ) async {
      _pantalla(tester, const Size(360, 640), 2);
      final largo = '${List.filled(70, 'a').join()}@ejemplo-de-dominio-muy-largo.com.uy';
      await _montar(tester, email: largo);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('configuracion_email')), findsOneWidget);
    });

    testWidgets('dos tocs seguidos en «Cerrar sesión» abren una sola hoja', (tester) async {
      _pantalla(tester, const Size(390, 844), 1);
      await _montar(tester);
      final pos = tester.getCenter(find.byKey(const Key('configuracion_cerrar_sesion')));
      await tester.tapAt(pos);
      await tester.tapAt(pos);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('configuracion_dialogo_cierre')), findsOneWidget);
    });

    testWidgets('la falla de cierre no expone el correo en el mensaje del aviso', (tester) async {
      const f = FailureCierreSesionSinConexion();
      expect(f.toString(), isNot(contains('@')));
      expect(f.mensaje, isNot(contains('@')));
    });
  });
}

Finder get _login => find.byKey(const Key('login_enviar'));
