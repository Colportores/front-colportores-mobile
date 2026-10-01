// QA de la vista 18 (#227, HU-AUTH-008): matriz de tamaños (360x640 y 412x915), texto al 200 %
// y cambios de estado con la pantalla abierta.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/asignacion_campania_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/estado_cuenta_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resumen_datos_locales.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/datos_locales_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/asignacion_campania_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

final _actualizar = find.byKey(const Key('espera_actualizar'));
final _login = find.byKey(const Key('login_enviar'));

/// Teléfono sin nada guardado: el cierre de sesión pide la confirmación común.
final class _SinDatosLocales implements DatosLocalesRepository {
  @override
  Future<Either<Failure, ResumenDatosLocales>> resumen() async => const Right(
    ResumenDatosLocales(
      personas: 0,
      visitas: 0,
      operacionesSinSincronizar: 0,
      hayBackupEnDrive: false,
    ),
  );

  @override
  Future<Either<Failure, ResultadoBorradoDatosLocales>> borrar({
    required bool incluirBackupDrive,
    bool reintento = false,
  }) async => const Right(ResultadoBorradoDatosLocales.completo);
}

late EstadoCuentaEnMemoria _backend;
late EstadoCuentaLocalEnMemoria _recordado;
late AsignacionCampaniaEnMemoria _asignacion;

/// El reloj de la pantalla de espera y del repositorio: los tests lo adelantan.
DateTime _ahora = DateTime(2026, 9, 30, 14, 30);

/// Monta la app y entra con la cuenta de Ana (a menos que [entrar] sea `false`).
Future<void> _montar(
  WidgetTester tester, {
  EstadoCuenta estado = EstadoCuenta.pendienteAsignacion,
  bool entrar = true,
}) async {
  _backend = EstadoCuentaEnMemoria(estado: estado);
  _recordado = EstadoCuentaLocalEnMemoria();
  _asignacion = AsignacionCampaniaEnMemoria();
  _ahora = DateTime(2026, 9, 30, 14, 30);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // HU-AUTH-009 (#27): la DB local se prepara antes de la pantalla principal; acá ya está.
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        ahoraEsperaProvider.overrideWithValue(() => _ahora),
        asignacionCampaniaDataSourceProvider.overrideWithValue(_asignacion),
        estadoCuentaRemoteDataSourceProvider.overrideWithValue(_backend),
        estadoCuentaLocalDataSourceProvider.overrideWithValue(_recordado),
        datosLocalesRepositoryProvider.overrideWithValue(_SinDatosLocales()),
      ],
      child: const ColportoresApp(),
    ),
  );
  await tester.pumpAndSettle();
  if (!entrar) return;
  await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
  await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
  await tester.tap(_login);
  await tester.pumpAndSettle();
}

Future<void> _deslizarParaRefrescar(WidgetTester tester) async {
  await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
  await tester.pumpAndSettle();
}

const _tamanios = [Size(360, 640), Size(412, 915)];

final _aviso = find.byKey(const Key('modulo_bloqueado_aviso'));

Future<void> _llegarA(WidgetTester tester, String artboard) async {
  switch (artboard) {
    case 'A01':
      await _montar(tester);
    case 'A02':
      await _montar(tester);
      _backend.demora = Completer<void>();
      await tester.tap(_actualizar);
      await tester.pump();
    case 'A03':
      await _montar(tester);
      await tester.tap(_actualizar);
      await tester.pumpAndSettle();
    case 'A04':
      await _montar(tester);
      _backend.simularSinConexion = true;
      await tester.tap(_actualizar);
      await tester.pumpAndSettle();
    case 'A05':
      await _montar(tester);
      _backend.falla = const ServidorException(status: 503);
      await tester.tap(_actualizar);
      await tester.pumpAndSettle();
    case 'A06':
      await _montar(tester, estado: EstadoCuenta.suspendida);
    case 'A07':
      await _montar(tester);
      _backend.estado = EstadoCuenta.activa;
      await tester.tap(_actualizar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    case 'sin-estado':
      await _montar(tester, entrar: false);
      _backend.simularSinConexion = true;
      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.tap(_login);
      await tester.pumpAndSettle();
    case 'modulo-bloqueado':
      await _montar(tester);
      await tester.tap(find.byKey(const Key('inicio_pestana_mapa')));
      await tester.pump();
  }
}

const _artboards = [
  'A01',
  'A02',
  'A03',
  'A04',
  'A05',
  'A06',
  'A07',
  'sin-estado',
  'modulo-bloqueado',
];

void _tamano(WidgetTester tester, Size tam, {double texto = 1}) {
  tester.view
    ..physicalSize = tam
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _cerrar(WidgetTester tester) async {
  _backend.demora?.complete();
  await tester.pumpAndSettle();
}

void main() {
  group('QA 18 — guías de accesibilidad por tamaño', () {
    for (final tam in _tamanios) {
      for (final artboard in _artboards) {
        testWidgets('$artboard a ${tam.width.toInt()}x${tam.height.toInt()}: toque, etiquetas y '
            'contraste', (tester) async {
          final semantica = tester.ensureSemantics();
          await _llegarA(tester, artboard);
          _tamano(tester, tam);
          await tester.pump();

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          expect(tester.takeException(), isNull);
          semantica.dispose();
          await _cerrar(tester);
        });
      }
    }
  });

  group('QA 18 — texto al 200 % a 360x640', () {
    for (final artboard in _artboards) {
      testWidgets('$artboard: sin overflow y se puede actuar', (tester) async {
        await _llegarA(tester, artboard);
        _tamano(tester, const Size(360, 640), texto: 2);
        // «Consultando…» tiene un indicador que nunca se asienta.
        await (artboard == 'A02' ? tester.pump() : tester.pumpAndSettle());
        expect(tester.takeException(), isNull, reason: artboard);

        if (artboard == 'A01' || artboard == 'A03' || artboard == 'A04') {
          await tester.ensureVisible(_actualizar);
          await tester.pumpAndSettle();
          expect(_actualizar, findsOneWidget);
        }
        if (artboard == 'A06') {
          final ir = find.byKey(const Key('espera_ir_a_configuracion'));
          await tester.ensureVisible(ir);
          await tester.pumpAndSettle();
          expect(ir, findsOneWidget);
        }
        if (artboard == 'modulo-bloqueado') expect(_aviso, findsOneWidget);
        expect(tester.takeException(), isNull, reason: artboard);
        await _cerrar(tester);
      });
    }

    testWidgets('el engranaje de Configuración sigue a mano y dice su nombre', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester);
      _tamano(tester, const Size(360, 640), texto: 2);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Configuración'), findsOneWidget);
      await tester.tap(find.byKey(const Key('espera_configuracion')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('configuracion_pagina')), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantica.dispose();
    });
  });

  group('QA 18 — cambios de estado con la pantalla abierta', () {
    testWidgets('pendiente → suspendida → pendiente: el aviso viejo no reaparece (menor de la '
        'revisión: no se reproduce por la UI)', (tester) async {
      await _montar(tester);
      _backend.falla = const ServidorException(status: 503);
      await tester.tap(_actualizar);
      await tester.pumpAndSettle();
      expect(find.text('No pudimos revisar tu cuenta'), findsOneWidget);

      _backend.falla = null;
      _backend.estado = EstadoCuenta.suspendida;
      await tester.tap(_actualizar);
      await tester.pumpAndSettle();
      expect(find.text('Cuenta suspendida'), findsOneWidget);

      _backend.estado = EstadoCuenta.pendienteAsignacion;
      _ahora = DateTime(2026, 9, 30, 14, 50);
      await _deslizarParaRefrescar(tester);

      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(find.text('Revisado recién, a las 14:50.'), findsOneWidget);
      expect(find.text('Probá de nuevo en unos minutos.'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('suspendida: la actualización fallida avisa y deja la salida a Configuración', (
      tester,
    ) async {
      await _montar(tester, estado: EstadoCuenta.suspendida);
      _backend.simularSinConexion = true;

      await _deslizarParaRefrescar(tester);

      expect(find.byKey(const Key('espera_resultado')), findsOneWidget);
      expect(find.text('Cuenta suspendida'), findsOneWidget);
      expect(find.byKey(const Key('espera_ir_a_configuracion')), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('error a mitad de la consulta y reintento exitoso: ningún estado trabado', (
      tester,
    ) async {
      await _montar(tester);
      _backend.falla = const ServidorException(status: 500);
      await tester.tap(_actualizar);
      await tester.pumpAndSettle();
      expect(find.text('Reintentar'), findsOneWidget);

      _backend.falla = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('espera_aun_no_asignado')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('los cuatro módulos bloqueados seguidos: un solo aviso, sin overflow a 200 %', (
      tester,
    ) async {
      await _montar(tester);
      _tamano(tester, const Size(360, 640), texto: 2);
      await tester.pumpAndSettle();
      for (final k in ['mapa', 'lista', 'agenda', 'ventas']) {
        await tester.tap(find.byKey(Key('inicio_pestana_$k')));
        await tester.pump();
      }
      expect(_aviso, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
    });
  });
}
