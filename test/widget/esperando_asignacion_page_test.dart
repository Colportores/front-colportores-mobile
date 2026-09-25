// HU-AUTH-008 — Cuenta pendiente hasta asignación a campaña, con la app montada.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/estado_cuenta_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/estado_cuenta_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_cuenta.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resumen_datos_locales.dart';
import 'package:colportores_mobile/features/auth/domain/repositories/datos_locales_repository.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/esperando_asignacion_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

final _titulo = find.byKey(const Key('espera_titulo'));
final _actualizar = find.byKey(const Key('espera_actualizar'));
final _principal = find.byKey(const Key('inicio_email'));
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
  }) async => const Right(ResultadoBorradoDatosLocales.completo);
}

late EstadoCuentaEnMemoria _backend;
late EstadoCuentaLocalEnMemoria _recordado;

/// Monta la app y entra con la cuenta de Ana (a menos que [entrar] sea `false`).
Future<void> _montar(
  WidgetTester tester, {
  EstadoCuenta estado = EstadoCuenta.pendienteAsignacion,
  bool entrar = true,
}) async {
  _backend = EstadoCuentaEnMemoria(estado: estado);
  _recordado = EstadoCuentaLocalEnMemoria();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // HU-AUTH-009 (#27): la DB local se prepara antes de la pantalla principal.
        dbLocalRepositoryProvider.overrideWithValue(DbLocalRepositoryEnMemoria()),
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
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
  await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
  await tester.pumpAndSettle();
}

void main() {
  group('HU-AUTH-008 — criterios de aceptación', () {
    testWidgets('Escenario: Login con cuenta en PENDIENTE_ASIGNACION — navega a "Esperando '
        'asignación" y los módulos de campo no aparecen', (tester) async {
      await _montar(tester);

      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(
        find.text(
          'Tu cuenta fue creada. Estamos esperando que tu coordinador te asigne a una campaña.',
        ),
        findsOneWidget,
      );
      expect(_principal, findsNothing);
      expect(find.byKey(const Key('inicio_configuracion')), findsNothing);
    });

    testWidgets('Escenario: Transición a ACTIVA mientras el app está abierto — al actualizar, '
        'navega a la pantalla principal', (tester) async {
      await _montar(tester);
      _backend.estado = EstadoCuenta.activa;

      await tester.tap(_actualizar);
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(_titulo, findsNothing);
    });

    testWidgets(
      'Escenario: Pull-to-refresh manual — si sigue pendiente muestra "Aún no asignado"',
      (tester) async {
        await _montar(tester);
        final antes = _backend.consultas;

        await _deslizarParaRefrescar(tester);

        expect(_backend.consultas, antes + 1, reason: 'consulta el estado en el backend');
        expect(find.text('Aún no asignado'), findsOneWidget);
        expect(find.text('Esperando asignación'), findsOneWidget);
      },
    );

    testWidgets('Escenario: Pull-to-refresh manual — si pasó a ACTIVA navega a la pantalla '
        'principal', (tester) async {
      await _montar(tester);
      _backend.estado = EstadoCuenta.activa;

      await _deslizarParaRefrescar(tester);

      expect(_principal, findsOneWidget);
      expect(find.text('Aún no asignado'), findsNothing);
    });

    testWidgets('Escenario: Acceso intentado a módulo de campo (gate) — mientras la cuenta esté '
        'pendiente, la raíz no deja llegar a la pantalla principal aunque se reabra', (
      tester,
    ) async {
      await _montar(tester);

      // Reabrir: la raíz vuelve a resolver la sesión y el estado desde cero.
      final container = ProviderScope.containerOf(tester.element(_titulo));
      container.invalidate(estadoCuentaProvider);
      await tester.pumpAndSettle();

      expect(_principal, findsNothing);
      expect(_titulo, findsOneWidget);
    });

    testWidgets('Escenario: Edge - cuenta SUSPENDIDA — muestra "Tu cuenta está suspendida. '
        'Contactá al administrador." sin módulos de campo', (tester) async {
      await _montar(tester, estado: EstadoCuenta.suspendida);

      expect(find.text('Tu cuenta está suspendida. Contactá al administrador.'), findsOneWidget);
      expect(_principal, findsNothing);
      expect(find.byKey(const Key('espera_configuracion')), findsOneWidget);
    });

    testWidgets('con la cuenta ACTIVA entra directo a la pantalla principal', (tester) async {
      await _montar(tester, estado: EstadoCuenta.activa);

      expect(_principal, findsOneWidget);
      expect(_titulo, findsNothing);
    });
  });

  group('Estados', () {
    testWidgets('cargando: mientras consulta al entrar, un indicador de progreso', (tester) async {
      await _montar(tester, entrar: false);
      _backend.demora = Completer<void>();

      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.tap(_login);
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(_principal, findsNothing);

      _backend.demora!.complete();
      await tester.pumpAndSettle();
      expect(_titulo, findsOneWidget);
    });

    testWidgets('actualizando: el botón se deshabilita y dice "Consultando…"', (tester) async {
      await _montar(tester);
      _backend.demora = Completer<void>();

      await tester.tap(_actualizar);
      await tester.pump();

      expect(find.text('Consultando…'), findsOneWidget);
      expect(tester.widget<FilledButton>(_actualizar).onPressed, isNull);

      _backend.demora!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Actualizar'), findsOneWidget);
    });

    testWidgets('sin conexión al actualizar: dice qué pasa y qué hacer, y deja la pantalla como '
        'estaba', (tester) async {
      await _montar(tester);
      _backend.simularSinConexion = true;

      await tester.tap(_actualizar);
      await tester.pumpAndSettle();

      expect(find.text('Sin conexión. Reintentá cuando tengas señal'), findsOneWidget);
      expect(find.text('Esperando asignación'), findsOneWidget);
    });

    testWidgets('sin conexión al entrar y sin estado conocido: no inventa uno, lo explica y deja '
        'reintentar', (tester) async {
      await _montar(tester, entrar: false);
      _backend.simularSinConexion = true;

      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.tap(_login);
      await tester.pumpAndSettle();

      expect(find.text('No pudimos revisar tu cuenta'), findsOneWidget);
      expect(find.text(TextosEsperaAsignacion.sinEstadoSinConexion), findsOneWidget);
      expect(_principal, findsNothing);

      _backend.simularSinConexion = false;
      await tester.tap(_actualizar);
      await tester.pumpAndSettle();
      expect(find.text('Esperando asignación'), findsOneWidget);
    });

    testWidgets('sin conexión al reabrir: rige el último estado que informó el backend', (
      tester,
    ) async {
      await _montar(tester, estado: EstadoCuenta.activa);
      expect(_principal, findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(_principal));
      final usuarioId = container.read(sesionProvider).value!.usuarioId;
      expect(await _recordado.leer(usuarioId), EstadoCuenta.activa);

      _backend
        ..simularSinConexion = true
        ..estado = EstadoCuenta.pendienteAsignacion;
      container.invalidate(estadoCuentaProvider);
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget, reason: 'el colportor sin señal no queda afuera');
    });

    testWidgets('error del backend sin estado conocido: explica y sugiere avisar al coordinador', (
      tester,
    ) async {
      await _montar(tester, entrar: false);
      _backend.falla = const ServidorException(status: 503);

      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.tap(_login);
      await tester.pumpAndSettle();

      expect(find.text(TextosEsperaAsignacion.sinEstado), findsOneWidget);
    });
  });

  testWidgets('Configuración sigue disponible: cerrar sesión desde la pantalla de espera', (
    tester,
  ) async {
    await _montar(tester);

    await tester.tap(find.byKey(const Key('espera_ir_a_configuracion')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('configuracion_cerrar_sesion')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('configuracion_dialogo_confirmar')));
    await tester.pumpAndSettle();

    expect(_login, findsOneWidget);
  });

  group('Accesibilidad', () {
    // 390x844 (convención del carril, issue #64): sin fijar el tamaño, `meetsGuideline` corría
    // con el viewport default de test (no un teléfono real). Paleta única 1b (#121): sin tema
    // oscuro, así que ya no hace falta correr esto por brillo.
    for (final estado in [EstadoCuenta.pendienteAsignacion, EstadoCuenta.suspendida]) {
      testWidgets('${estado.name}: tamaño de toque, etiquetas y contraste en 390x844', (
        tester,
      ) async {
        final semantica = tester.ensureSemantics();
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _montar(tester, estado: estado);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
      });
    }

    testWidgets('el título se anuncia como encabezado', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester);

      expect(tester.getSemantics(_titulo), isSemantics(isHeader: true));
      semantica.dispose();
    });

    for (final estado in [EstadoCuenta.pendienteAsignacion, EstadoCuenta.suspendida]) {
      testWidgets('${estado.name}: sin overflow con el texto al 200 % en 360x740', (tester) async {
        // El login desborda en pantallas chicas (arreglado en #113): se entra con la pantalla y el
        // texto normales, y recién en la pantalla de espera se achica y se agranda el texto.
        await _montar(tester, estado: estado);
        expect(tester.takeException(), isNull);
        tester.view
          ..physicalSize = const Size(360, 740)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();

        expect(_titulo, findsOneWidget);
        expect(tester.takeException(), isNull);

        _backend.demora = Completer<void>();
        await tester.scrollUntilVisible(_actualizar, 100);
        await tester.tap(_actualizar);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'estado "Consultando…"');
        _backend.demora!.complete();
        await tester.pumpAndSettle();
      });
    }
  });
}
