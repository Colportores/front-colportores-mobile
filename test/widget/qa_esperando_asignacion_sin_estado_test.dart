// QA de la vista 18, seguimiento del 02/10 (#227, HU-AUTH-008): sin conexión y sin estado de
// cuenta conocido. Matriz de tamaños y texto al 200 % de las variantes sin estado, el escenario de
// la HU con su texto literal, la salida de cada variante y los casos límite de «Reintentar».
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/asignacion_campania_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/estado_cuenta_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resumen_datos_locales.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/datos_locales_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/esperando_asignacion_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/asignacion_campania_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/widgets/aviso_modulo_bloqueado.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

final _titulo = find.byKey(const Key('espera_titulo'));
final _actualizar = find.byKey(const Key('espera_actualizar'));
final _principal = find.byKey(const Key('inicio_principal'));
final _login = find.byKey(const Key('login_enviar'));
final _sinConexion = find.byKey(const Key('espera_sin_conexion'));
final _error = find.byKey(const Key('espera_error'));

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

/// Un backend que revienta con algo que no es de la app (no una `AuthRemoteException`).
final class _Revienta implements EstadoCuentaRemoteDataSource {
  bool revienta = true;

  @override
  Future<EstadoCuenta> consultar() async {
    if (revienta) throw StateError('boom');
    return EstadoCuenta.pendienteAsignacion;
  }
}

late EstadoCuentaEnMemoria _backend;
late EstadoCuentaLocalEnMemoria _recordado;
late AsignacionCampaniaEnMemoria _asignacion;
DateTime _ahora = DateTime(2026, 10, 2, 14, 30);

Future<void> _montar(
  WidgetTester tester, {
  EstadoCuenta estado = EstadoCuenta.pendienteAsignacion,
  EstadoCuentaRemoteDataSource? remoto,
}) async {
  _backend = EstadoCuentaEnMemoria(estado: estado);
  _recordado = EstadoCuentaLocalEnMemoria();
  _asignacion = AsignacionCampaniaEnMemoria();
  _ahora = DateTime(2026, 10, 2, 14, 30);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        ahoraEsperaProvider.overrideWithValue(() => _ahora),
        asignacionCampaniaDataSourceProvider.overrideWithValue(_asignacion),
        estadoCuentaRemoteDataSourceProvider.overrideWithValue(remoto ?? _backend),
        estadoCuentaLocalDataSourceProvider.overrideWithValue(_recordado),
        datosLocalesRepositoryProvider.overrideWithValue(_SinDatosLocales()),
      ],
      child: const ColportoresApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _entrar(WidgetTester tester, {bool esperar = true}) async {
  await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
  await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
  await tester.tap(_login);
  if (esperar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}

/// Entra sin red y sin haber consultado nunca el estado: la variante nueva de la decisión del 02/10.
Future<void> _entrarSinConexion(WidgetTester tester) async {
  await _montar(tester);
  _backend.simularSinConexion = true;
  await _entrar(tester);
}

Future<void> _tocarReintentar(WidgetTester tester) async {
  await tester.ensureVisible(_actualizar);
  await tester.tap(_actualizar);
  await tester.pumpAndSettle();
}

Future<void> _deslizarParaRefrescar(WidgetTester tester) async {
  await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
  await tester.pumpAndSettle();
}

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

const _variantes = [
  'sin-conexion',
  'error-servidor',
  'consultando',
  'reintento-sin-red',
  'modulo-bloqueado',
];

Future<void> _llegarA(WidgetTester tester, String variante) async {
  switch (variante) {
    case 'sin-conexion':
      await _entrarSinConexion(tester);
    case 'error-servidor':
      await _montar(tester);
      _backend.falla = const ServidorException(status: 503);
      await _entrar(tester);
    case 'consultando':
      await _entrarSinConexion(tester);
      _backend.demora = Completer<void>();
      await tester.tap(_actualizar);
      await tester.pump();
    case 'reintento-sin-red':
      await _entrarSinConexion(tester);
      await _tocarReintentar(tester);
    case 'modulo-bloqueado':
      await _entrarSinConexion(tester);
      await tester.tap(find.byKey(const Key('inicio_pestana_mapa')));
      await tester.pump();
  }
}

void main() {
  const matriz = [
    (Size(360, 640), 1.0, '360x640'),
    (Size(360, 640), 2.0, '360x640 con texto 2.0'),
    (Size(412, 915), 1.0, '412x915'),
  ];

  group('QA 18 (02/10) — guías de accesibilidad y tamaños de las variantes sin estado', () {
    for (final (tam, texto, nombre) in matriz) {
      for (final variante in _variantes) {
        testWidgets('$variante a $nombre: toque, etiquetas, contraste y sin overflow', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          try {
            await _llegarA(tester, variante);
            _tamano(tester, tam, texto: texto);
            await tester.pump(const Duration(milliseconds: 500));

            expect(tester.takeException(), isNull, reason: '$variante a $nombre');
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));

            if (variante != 'consultando' && variante != 'modulo-bloqueado') {
              await tester.ensureVisible(_actualizar);
              await tester.pump();
              expect(_actualizar, findsOneWidget);
              expect(tester.takeException(), isNull);
            }
          } finally {
            semantica.dispose();
          }
          await _cerrar(tester);
        });
      }
    }
  });

  group('QA 18 (02/10) — criterios de aceptación: sin conexión y estado nunca consultado', () {
    testWidgets(
      'Dado que abro la app sin conexión y nunca se consultó el estado, Entonces aviso de sin '
      'conexión que dice qué pasa y qué hacer, Y no afirma «Esperando asignación»',
      (tester) async {
        final semantica = tester.ensureSemantics();
        try {
          await _entrarSinConexion(tester);

          // Qué pasa y qué hacer, con los textos de la decisión.
          expect(find.text('Sin conexión'), findsOneWidget);
          expect(
            find.text(
              'No hay conexión para revisar tu cuenta. Conectate a internet y tocá Reintentar.',
            ),
            findsOneWidget,
          );
          expect(find.text('Reintentar'), findsOneWidget);
          expect(find.text('Actualizar'), findsNothing);

          // No afirma nada de la cuenta, ni en pantalla ni en la semántica.
          expect(find.textContaining('Esperando asignación'), findsNothing);
          expect(find.textContaining('CUENTA PENDIENTE'), findsNothing);
          expect(find.textContaining('Tu cuenta fue creada'), findsNothing);
          expect(find.text('Cuenta creada'), findsNothing);
          expect(find.byKey(const Key('espera_linea_de_tiempo')), findsNothing);
          expect(find.text('No pudimos revisar tu cuenta'), findsNothing);
          expect(find.bySemanticsLabel(RegExp('Esperando asignación')), findsNothing);
          expect(_principal, findsNothing);
        } finally {
          semantica.dispose();
        }
      },
    );

    testWidgets(
      'el aviso se anuncia (liveRegion), el título es encabezado y el botón tiene nombre',
      (tester) async {
        final semantica = tester.ensureSemantics();
        try {
          await _entrarSinConexion(tester);

          expect(tester.getSemantics(_sinConexion), isSemantics(isLiveRegion: true));
          expect(tester.getSemantics(_titulo), isSemantics(isHeader: true));
          expect(find.bySemanticsLabel('Reintentar'), findsOneWidget);
        } finally {
          semantica.dispose();
        }
      },
    );

    testWidgets('«Reintentar» no queda deshabilitado y la barra inferior sigue con los módulos '
        'bloqueados', (tester) async {
      await _entrarSinConexion(tester);

      expect(tester.widget<FilledButton>(_actualizar).onPressed, isNotNull);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(4));
      expect(find.byKey(const Key('espera_configuracion')), findsOneWidget);
    });
  });

  group('QA 18 (02/10) — salidas de «Reintentar» desde sin estado conocido', () {
    testWidgets('con red y cuenta pendiente: pasa a «Esperando asignación» con «Aún no asignado»', (
      tester,
    ) async {
      await _entrarSinConexion(tester);
      _backend.simularSinConexion = false;

      await _tocarReintentar(tester);

      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(find.text('Aún no asignado'), findsOneWidget);
      expect(find.text('Revisado recién, a las 14:30.'), findsOneWidget);
      expect(_sinConexion, findsNothing);
      expect(find.text('Sin conexión'), findsNothing);
      expect(find.text('Actualizar'), findsOneWidget);
    });

    testWidgets('con red y cuenta activa: entra directo a la pantalla principal', (tester) async {
      await _entrarSinConexion(tester);
      _backend
        ..simularSinConexion = false
        ..estado = EstadoCuenta.activa;

      await _tocarReintentar(tester);

      expect(_principal, findsOneWidget);
      expect(_titulo, findsNothing);
    });

    testWidgets('con red y cuenta suspendida: «Cuenta suspendida» con la salida a Configuración', (
      tester,
    ) async {
      await _entrarSinConexion(tester);
      _backend
        ..simularSinConexion = false
        ..estado = EstadoCuenta.suspendida;

      await _tocarReintentar(tester);

      expect(find.text('Cuenta suspendida'), findsOneWidget);
      expect(find.text('Tu cuenta está suspendida. Contactá al administrador.'), findsOneWidget);
      expect(find.byKey(const Key('espera_ir_a_configuracion')), findsOneWidget);
      expect(find.text('Sin conexión'), findsNothing);
    });

    testWidgets('deslizar para refrescar también reintenta desde sin estado conocido', (
      tester,
    ) async {
      await _entrarSinConexion(tester);
      final antes = _backend.consultas;
      _backend.simularSinConexion = false;

      await _deslizarParaRefrescar(tester);

      expect(_backend.consultas, antes + 1);
      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(_sinConexion, findsNothing);
    });

    testWidgets(
      'servidor, sin red, servidor y red de nuevo: un solo aviso por vez, nunca apilados',
      (tester) async {
        await _montar(tester);
        _backend.falla = const ServidorException(status: 503);
        await _entrar(tester);
        expect(_error, findsOneWidget);
        expect(_sinConexion, findsNothing);

        _backend
          ..falla = null
          ..simularSinConexion = true;
        await _tocarReintentar(tester);
        expect(_sinConexion, findsOneWidget);
        expect(_error, findsNothing);
        expect(find.text('Sin conexión'), findsOneWidget);

        _backend
          ..simularSinConexion = false
          ..falla = const ServidorException(status: 500);
        await _tocarReintentar(tester);
        expect(_error, findsOneWidget);
        expect(_sinConexion, findsNothing);
        expect(find.text('Sin conexión'), findsNothing);
        expect(find.text('No pudimos revisar tu cuenta'), findsOneWidget);

        _backend.falla = null;
        await _tocarReintentar(tester);
        expect(find.text('Esperando asignación'), findsOneWidget);
        expect(_error, findsNothing);
        expect(_sinConexion, findsNothing);
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets('un error que no es de la app al consultar al entrar: explica, deja reintentar y '
        'se recupera', (tester) async {
      final remoto = _Revienta();
      await _montar(tester, remoto: remoto);
      await _entrar(tester);

      expect(find.text(TextosEsperaAsignacion.sinEstado), findsOneWidget);
      expect(_error, findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _tocarReintentar(tester);
      expect(find.text(TextosEsperaAsignacion.sinEstado), findsOneWidget);
      expect(tester.widget<FilledButton>(_actualizar).onPressed, isNotNull);

      remoto.revienta = false;
      await _tocarReintentar(tester);
      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(_error, findsNothing);
    });
  });

  group('QA 18 (02/10) — casos límite sin estado conocido', () {
    testWidgets('la consulta termina mientras el colportor está en Configuración: al volver ve el '
        'resultado', (tester) async {
      await _entrarSinConexion(tester);
      _backend.demora = Completer<void>();
      _backend.simularSinConexion = false;
      await tester.tap(_actualizar);
      await tester.pump();
      expect(find.text('Consultando…'), findsOneWidget);

      await tester.tap(find.byKey(const Key('espera_configuracion')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('configuracion_pagina')), findsOneWidget);

      _backend.demora!.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('configuracion_atras')));
      await tester.pumpAndSettle();

      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(find.text('Consultando…'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Configuración sigue a mano sin estado conocido: se puede cerrar sesión', (
      tester,
    ) async {
      await _entrarSinConexion(tester);

      await tester.tap(find.byKey(const Key('espera_configuracion')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('configuracion_cerrar_sesion')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('configuracion_dialogo_confirmar')));
      await tester.pumpAndSettle();

      expect(_login, findsOneWidget);
    });

    testWidgets('cerrar sesión con una consulta en vuelo: la respuesta tardía no rompe nada y al '
        'volver a entrar se consulta de nuevo', (tester) async {
      await _entrarSinConexion(tester);
      _backend.demora = Completer<void>();
      _backend.simularSinConexion = false;
      await tester.tap(_actualizar);
      await tester.pump();

      await tester.tap(find.byKey(const Key('espera_configuracion')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('configuracion_cerrar_sesion')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('configuracion_dialogo_confirmar')));
      await tester.pumpAndSettle();
      expect(_login, findsOneWidget);

      _backend.demora!.complete();
      await tester.pumpAndSettle();
      expect(_login, findsOneWidget);
      expect(tester.takeException(), isNull);

      _backend.demora = null;
      final antes = _backend.consultas;
      await _entrar(tester);
      expect(_backend.consultas, greaterThan(antes));
      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(find.text('Sin conexión'), findsNothing);
    });

    testWidgets('«Hoy» no hace nada sin estado conocido: es esta pantalla', (tester) async {
      await _entrarSinConexion(tester);

      await tester.tap(find.byKey(const Key('inicio_pestana_hoy')));
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Sin conexión'), findsOneWidget);
    });

    testWidgets('doble toque en «Reintentar» con falla a mitad de la consulta: una sola consulta y '
        'el botón vuelve a andar', (tester) async {
      await _entrarSinConexion(tester);
      final antes = _backend.consultas;
      _backend
        ..demora = Completer<void>()
        ..simularSinConexion = false
        ..falla = const ServidorException(status: 503);

      await tester.tap(_actualizar);
      await tester.pump();
      await tester.tap(_actualizar, warnIfMissed: false);
      await tester.pump();
      _backend.demora!.complete();
      await tester.pumpAndSettle();

      expect(_backend.consultas, antes + 1);
      expect(_error, findsOneWidget);
      expect(tester.widget<FilledButton>(_actualizar).onPressed, isNotNull);
      expect(find.text('Consultando…'), findsNothing);
    });

    testWidgets(
      'QA #227: tocar un módulo bloqueado sin estado conocido no dice que la cuenta espera '
      'asignación',
      (tester) async {
        await _entrarSinConexion(tester);

        await tester.tap(find.byKey(const Key('inicio_pestana_mapa')));
        await tester.pump();

        // La HU: con el estado nunca consultado la app no afirma «Esperando asignación». El aviso
        // repite el de la pantalla para la misma causa (decisión del 02/10, #278).
        expect(find.text(TextosModuloBloqueado.pendiente), findsNothing);
        expect(find.byKey(const Key('modulo_bloqueado_aviso')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('modulo_bloqueado_aviso')),
            matching: find.text(TextosEsperaAsignacion.sinConexionSinEstado),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'QA #227: mientras consulta el estado al entrar hay texto de contexto, no un spinner solo',
      (tester) async {
        await _montar(tester);
        _backend.demora = Completer<void>();

        await _entrar(tester, esperar: false);

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(Scaffold),
            matching: find.text(TextosEsperaAsignacion.revisando),
          ),
          findsOneWidget,
          reason: 'el spinner del arranque dice qué está esperando',
        );
        await _cerrar(tester);
      },
    );
  });
}
