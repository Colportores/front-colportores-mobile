// HU-AUTH-008 — Cuenta pendiente hasta asignación a campaña, con la app montada. Vista 18 (#227):
// un grupo por artboard (A01 a A07) y los casos límite de cada flujo.
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
import 'package:colportores_mobile/features/auth/presentation/pages/esperando_asignacion_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/asignacion_campania_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/estado_cuenta_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/inicio/presentation/widgets/barra_pestanas_inicio.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

final _titulo = find.byKey(const Key('espera_titulo'));
final _actualizar = find.byKey(const Key('espera_actualizar'));
final _principal = find.byKey(const Key('inicio_principal'));
final _login = find.byKey(const Key('login_enviar'));
final _scrollable = find.byType(Scrollable).first;

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

/// Deja correr el gesto de deslizar hasta que el indicador dispara la consulta (sin `pumpAndSettle`:
/// con una consulta en curso el indicador no se queda quieto).
Future<void> _esperarRefresco(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _deslizarParaRefrescar(WidgetTester tester) async {
  await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
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

      expect(find.text(TextosEsperaAsignacion.sinEstadoSinConexion), findsOneWidget);
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

      // Decisión de Cristian (02/10): un aviso de sin conexión explícito, no el genérico.
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(find.text('No pudimos revisar tu cuenta'), findsNothing);
      expect(find.text(TextosEsperaAsignacion.sinConexionSinEstado), findsOneWidget);
      expect(find.byKey(const Key('espera_sin_conexion')), findsOneWidget);
      expect(find.byKey(const Key('espera_error')), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(_principal, findsNothing);

      _backend.simularSinConexion = false;
      await tester.tap(_actualizar);
      await tester.pumpAndSettle();
      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(find.byKey(const Key('espera_sin_conexion')), findsNothing);
    });

    testWidgets('sin conexión y sin estado: dice qué pasa y qué hacer', (tester) async {
      await _montar(tester, entrar: false);
      _backend.simularSinConexion = true;
      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.tap(_login);
      await tester.pumpAndSettle();

      const texto = TextosEsperaAsignacion.sinConexionSinEstado;
      expect(texto, contains('No hay conexión para revisar tu cuenta'));
      expect(texto, contains('Conectate'));
      expect(texto, contains('Reintentar'), reason: 'nombra el botón que hay en pantalla');
    });

    testWidgets('sin conexión y sin estado: si «Reintentar» sigue sin red, queda igual y se puede '
        'volver a tocar; si falla el servidor, pasa al error genérico', (tester) async {
      await _montar(tester, entrar: false);
      _backend.simularSinConexion = true;
      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.tap(_login);
      await tester.pumpAndSettle();

      await tester.tap(_actualizar);
      await tester.pumpAndSettle();
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(tester.widget<FilledButton>(_actualizar).onPressed, isNotNull);

      _backend.simularSinConexion = false;
      _backend.falla = const ServidorException(status: 503);
      await tester.tap(_actualizar);
      await tester.pumpAndSettle();
      expect(find.text('Sin conexión'), findsNothing);
      expect(find.text('No pudimos revisar tu cuenta'), findsOneWidget);
      expect(find.byKey(const Key('espera_sin_conexion')), findsNothing);
      expect(tester.widget<FilledButton>(_actualizar).onPressed, isNotNull);
    });

    testWidgets('sin conexión y sin estado: doble toque en «Reintentar» consulta una sola vez', (
      tester,
    ) async {
      await _montar(tester, entrar: false);
      _backend.simularSinConexion = true;
      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.tap(_login);
      await tester.pumpAndSettle();
      final antes = _backend.consultas;

      _backend.demora = Completer<void>();
      await tester.tap(_actualizar);
      await tester.pump();
      await tester.tap(_actualizar, warnIfMissed: false);
      await tester.pump();
      expect(find.text('Consultando…'), findsOneWidget);
      expect(
        find.text('Sin conexión'),
        findsNothing,
        reason: 'mientras consulta no hay aviso viejo',
      );

      _backend.demora!.complete();
      await tester.pumpAndSettle();
      expect(_backend.consultas, antes + 1);
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(tester.widget<FilledButton>(_actualizar).onPressed, isNotNull);
    });

    testWidgets('sin conexión y sin estado: volver atrás y reentrar vuelve a mostrar el aviso', (
      tester,
    ) async {
      await _montar(tester, entrar: false);
      _backend.simularSinConexion = true;
      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.tap(_login);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('espera_configuracion')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('configuracion_pagina')), findsOneWidget);

      await tester.tap(find.byKey(const Key('configuracion_atras')));
      await tester.pumpAndSettle();

      expect(find.text('Sin conexión'), findsOneWidget);
      expect(find.text(TextosEsperaAsignacion.sinConexionSinEstado), findsOneWidget);
    });

    testWidgets('sin conexión y sin estado: cumple las guías y no desborda con texto al 200 %', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _montar(tester, entrar: false);
      _backend.simularSinConexion = true;
      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.tap(_login);
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      tester.view
        ..physicalSize = const Size(360, 740)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantica.dispose();
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

    await tester.tap(find.byKey(const Key('espera_configuracion')));
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

        if (estado == EstadoCuenta.pendienteAsignacion) {
          _backend.demora = Completer<void>();
          await tester.scrollUntilVisible(_actualizar, 100, scrollable: _scrollable);
          await tester.tap(_actualizar);
          await tester.pump();
          expect(tester.takeException(), isNull, reason: 'estado "Consultando…"');
        }
        _backend.demora?.complete();
        await tester.pumpAndSettle();
      });
    }
  });

  group('Vista 18 — A01 Pendiente', () {
    testWidgets('A01: cuenta pendiente, texto completo, línea de tiempo y «Actualizar»', (
      tester,
    ) async {
      await _montar(tester);

      expect(find.text('CUENTA PENDIENTE'), findsOneWidget);
      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(find.byKey(const Key('espera_mensaje')), findsOneWidget);
      expect(
        find.text(
          'Cuando te asigne vas a poder empezar a trabajar. Deslizá hacia abajo o tocá '
          'Actualizar para revisar.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cuenta creada'), findsOneWidget);
      expect(find.text('Esperando asignación · ahora'), findsOneWidget);
      expect(find.text('Depende de tu coordinador.'), findsOneWidget);
      expect(find.text('Listo para trabajar'), findsOneWidget);
      expect(find.text('Última revisión: hoy a las 14:30'), findsOneWidget);
      expect(find.text('Actualizar'), findsOneWidget);
      expect(find.byKey(const Key('espera_configuracion')), findsOneWidget);
    });

    testWidgets('A01: la barra inferior muestra «Hoy» y los cuatro módulos bloqueados', (
      tester,
    ) async {
      await _montar(tester);

      for (final pestana in PestanaInicio.values) {
        expect(find.byKey(Key('inicio_pestana_${pestana.name}')), findsOneWidget);
      }
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(4));
      expect(find.byIcon(Icons.home), findsOneWidget, reason: '«Hoy» sin candado');
    });

    test('la última revisión se dice como hoy, ayer o con la fecha', () {
      final ahora = DateTime(2026, 9, 30, 9, 5);
      expect(
        TextosEsperaAsignacion.ultimaRevision(DateTime(2026, 9, 30, 14, 30), ahora),
        'Última revisión: hoy a las 14:30',
      );
      expect(
        TextosEsperaAsignacion.ultimaRevision(DateTime(2026, 9, 29, 23, 59), ahora),
        'Última revisión: ayer a las 23:59',
      );
      expect(
        TextosEsperaAsignacion.ultimaRevision(DateTime(2026, 9, 7, 8, 5), ahora),
        'Última revisión: el 07/09 a las 08:05',
      );
    });
  });

  group('Vista 18 — A02 Consultando', () {
    testWidgets('A02: «Revisando con el servidor…» y el botón «Consultando…» deshabilitado, sin la '
        'línea de tiempo', (tester) async {
      await _montar(tester);
      _backend.demora = Completer<void>();

      await tester.tap(_actualizar);
      await tester.pump();

      expect(find.text('Revisando con el servidor…'), findsOneWidget);
      expect(find.text('Consultando…'), findsOneWidget);
      expect(tester.widget<FilledButton>(_actualizar).onPressed, isNull);
      expect(find.byKey(const Key('espera_linea_de_tiempo')), findsNothing);
      expect(find.byKey(const Key('espera_ayuda')), findsNothing);
      expect(find.byKey(const Key('espera_mensaje')), findsOneWidget);

      _backend.demora!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Revisando con el servidor…'), findsNothing);
    });

    testWidgets('deslizar para refrescar también consulta y muestra el avance', (tester) async {
      await _montar(tester);
      final antes = _backend.consultas;
      _backend.demora = Completer<void>();

      await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
      await _esperarRefresco(tester);

      expect(find.text('Revisando con el servidor…'), findsOneWidget);
      _backend.demora!.complete();
      await tester.pumpAndSettle();
      expect(_backend.consultas, antes + 1);
    });

    testWidgets('doble toque en «Actualizar»: una sola consulta', (tester) async {
      await _montar(tester);
      final antes = _backend.consultas;
      _backend.demora = Completer<void>();

      await tester.tap(_actualizar);
      await tester.tap(_actualizar, warnIfMissed: false);
      await tester.pump();
      _backend.demora!.complete();
      await tester.pumpAndSettle();

      expect(_backend.consultas, antes + 1);
    });

    testWidgets('deslizar mientras ya consulta (dos acciones seguidas): no pisa ni duplica la '
        'consulta', (tester) async {
      await _montar(tester);
      final antes = _backend.consultas;
      _backend.demora = Completer<void>();

      await tester.tap(_actualizar);
      await tester.pump();
      await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0, 400), 1000);
      await _esperarRefresco(tester);
      _backend.demora!.complete();
      await tester.pumpAndSettle();

      expect(_backend.consultas, antes + 1);
      expect(find.text('Aún no asignado'), findsOneWidget);
      expect(tester.widget<FilledButton>(_actualizar).onPressed, isNotNull);
    });
  });

  group('Vista 18 — A03 Aún no asignado', () {
    testWidgets('A03: «Aún no asignado» con la hora de la revisión y sin la línea de tiempo', (
      tester,
    ) async {
      await _montar(tester);
      _ahora = DateTime(2026, 9, 30, 14, 36);

      await tester.tap(_actualizar);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('espera_aun_no_asignado')), findsOneWidget);
      expect(find.text('Aún no asignado'), findsOneWidget);
      expect(find.text('Revisado recién, a las 14:36.'), findsOneWidget);
      expect(find.byKey(const Key('espera_linea_de_tiempo')), findsNothing);
      expect(find.text('Actualizar'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(4));
    });

    testWidgets('volver atrás y reentrar desde Configuración: la pantalla queda como estaba', (
      tester,
    ) async {
      await _montar(tester);
      await tester.tap(_actualizar);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('espera_configuracion')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('configuracion_atras')));
      await tester.pumpAndSettle();

      expect(find.text('Aún no asignado'), findsOneWidget);
      expect(find.byKey(const Key('espera_configuracion')), findsOneWidget);
    });
  });

  group('Vista 18 — A04 Sin conexión y A05 Error', () {
    testWidgets('A04: sin conexión explica qué hacer, conserva el título y deja «Actualizar»', (
      tester,
    ) async {
      await _montar(tester);
      _backend.simularSinConexion = true;

      await tester.tap(_actualizar);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('espera_sin_conexion')), findsOneWidget);
      expect(find.text(TextosEsperaAsignacion.sinEstadoSinConexion), findsOneWidget);
      expect(find.text('Esperando asignación'), findsOneWidget);
      expect(find.byKey(const Key('espera_mensaje')), findsNothing);
      expect(find.text('Actualizar'), findsOneWidget);
      expect(tester.widget<FilledButton>(_actualizar).onPressed, isNotNull);
    });

    testWidgets('A04: al volver la señal y actualizar, el aviso se va', (tester) async {
      await _montar(tester);
      _backend.simularSinConexion = true;
      await tester.tap(_actualizar);
      await tester.pumpAndSettle();

      _backend.simularSinConexion = false;
      await tester.tap(_actualizar);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('espera_sin_conexion')), findsNothing);
      expect(find.text('Aún no asignado'), findsOneWidget);
    });

    testWidgets('A05: error del servidor, «Probá de nuevo en unos minutos.» y «Reintentar»', (
      tester,
    ) async {
      await _montar(tester);
      _backend.falla = const ServidorException(status: 503);

      await tester.tap(_actualizar);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('espera_error')), findsOneWidget);
      expect(find.text('No pudimos revisar tu cuenta'), findsOneWidget);
      expect(find.text('Probá de nuevo en unos minutos.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Actualizar'), findsNothing);
    });

    testWidgets('A05: falla a mitad de la consulta: el botón vuelve a andar y «Reintentar» '
        'resuelve', (tester) async {
      await _montar(tester);
      _backend
        ..falla = const ServidorException(status: 503)
        ..demora = Completer<void>();

      await tester.tap(_actualizar);
      await tester.pump();
      expect(find.text('Consultando…'), findsOneWidget);
      _backend.demora!.complete();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'nada queda trabado');
      expect(tester.widget<FilledButton>(_actualizar).onPressed, isNotNull);

      _backend
        ..falla = null
        ..demora = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('espera_error')), findsNothing);
      expect(find.text('Aún no asignado'), findsOneWidget);
    });

    testWidgets('sin estado conocido (nunca se pudo consultar): no afirma «cuenta pendiente» y '
        'mantiene los módulos bloqueados', (tester) async {
      await _montar(tester, entrar: false);
      _backend.falla = const ServidorException(status: 503);
      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.tap(_login);
      await tester.pumpAndSettle();

      expect(find.text('CUENTA PENDIENTE'), findsNothing);
      expect(find.text('Esperando asignación'), findsNothing);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(4));
    });
  });

  group('Vista 18 — A06 Cuenta suspendida', () {
    testWidgets('A06: texto de la HU, solo «Ir a Configuración» y la barra bloqueada', (
      tester,
    ) async {
      await _montar(tester, estado: EstadoCuenta.suspendida);

      expect(find.text('CUENTA SUSPENDIDA'), findsOneWidget);
      expect(find.text('Cuenta suspendida'), findsOneWidget);
      expect(find.text('Tu cuenta está suspendida. Contactá al administrador.'), findsOneWidget);
      expect(find.text('Ir a Configuración'), findsOneWidget);
      expect(_actualizar, findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(4));
    });

    testWidgets('A06: «Ir a Configuración» abre Configuración y se puede volver', (tester) async {
      await _montar(tester, estado: EstadoCuenta.suspendida);

      await tester.tap(find.byKey(const Key('espera_ir_a_configuracion')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('configuracion_pagina')), findsOneWidget);
      await tester.tap(find.byKey(const Key('configuracion_atras')));
      await tester.pumpAndSettle();

      expect(find.text('Cuenta suspendida'), findsOneWidget);
    });

    testWidgets('tocar un módulo bloqueado con la cuenta suspendida dice que está suspendida', (
      tester,
    ) async {
      await _montar(tester, estado: EstadoCuenta.suspendida);

      await tester.tap(find.byKey(const Key('inicio_pestana_ventas')));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const Key('modulo_bloqueado_aviso')),
          matching: find.text('Tu cuenta está suspendida. Contactá al administrador.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'suspendida y reactivada con la app abierta: entra directo, sin «Ya te asignaron»',
      (tester) async {
        await _montar(tester, estado: EstadoCuenta.suspendida);
        _backend.estado = EstadoCuenta.activa;

        await _deslizarParaRefrescar(tester);

        expect(_principal, findsOneWidget);
        expect(find.text('Ya te asignaron'), findsNothing);
      },
    );
  });

  group('Vista 18 — módulos bloqueados', () {
    testWidgets('tocar un módulo bloqueado explica por qué, sin acumular avisos', (tester) async {
      await _montar(tester);

      await tester.tap(find.byKey(const Key('inicio_pestana_mapa')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('inicio_pestana_lista')));
      await tester.pump();

      expect(
        find.text('Disponible cuando tu coordinador te asigne a una campaña.'),
        findsOneWidget,
      );
      expect(_principal, findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('tocar «Hoy» no hace nada: es esta pantalla', (tester) async {
      await _montar(tester);

      await tester.tap(find.byKey(const Key('inicio_pestana_hoy')));
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
      expect(_titulo, findsOneWidget);
    });

    testWidgets('Configuración con la cuenta pendiente: barra con los módulos bloqueados; «Hoy» '
        'vuelve a la espera', (tester) async {
      await _montar(tester);
      await tester.tap(find.byKey(const Key('espera_configuracion')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inicio_barra')), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(4));

      await tester.tap(find.byKey(const Key('inicio_pestana_mapa')));
      await tester.pump();
      expect(
        find.text('Disponible cuando tu coordinador te asigne a una campaña.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('configuracion_pagina')), findsOneWidget);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inicio_pestana_hoy')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('configuracion_pagina')), findsNothing);
      expect(_titulo, findsOneWidget);
    });
  });

  group('Vista 18 — A07 Ya te asignaron', () {
    Future<void> asignar(WidgetTester tester) async {
      _backend.estado = EstadoCuenta.activa;
      await tester.tap(_actualizar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets(
      'A07: «Ya te asignaron» con la campaña y la zona, y después la pantalla principal',
      (tester) async {
        await _montar(tester);

        await asignar(tester);

        expect(find.byKey(const Key('cuenta_asignada')), findsOneWidget);
        expect(find.text('Ya te asignaron'), findsOneWidget);
        expect(find.text('Campaña Primavera 2026'), findsOneWidget);
        expect(find.text('Zona Centro · Montevideo'), findsOneWidget);
        expect(find.text('Abriendo tu pantalla principal…'), findsOneWidget);
        expect(_principal, findsNothing);

        await tester.pumpAndSettle();

        expect(_principal, findsOneWidget);
        expect(find.byKey(const Key('cuenta_asignada')), findsNothing);
      },
    );

    testWidgets('A07: sin la fuente de la asignación (llega con #62) no inventa campaña ni zona', (
      tester,
    ) async {
      await _montar(tester);
      _asignacion.asignacion = null;

      await asignar(tester);

      expect(find.text('Ya te asignaron'), findsOneWidget);
      expect(find.byKey(const Key('asignada_detalle')), findsNothing);
      await tester.pumpAndSettle();
      expect(_principal, findsOneWidget);
    });

    testWidgets('A07: si falla la consulta de la asignación, igual pasa a la principal', (
      tester,
    ) async {
      await _montar(tester);
      _asignacion.falla = StateError('sin red');

      await asignar(tester);
      expect(find.text('Ya te asignaron'), findsOneWidget);
      await tester.pumpAndSettle();

      expect(_principal, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('A07: la asignación llega tarde, después de pasar a la principal: no rompe', (
      tester,
    ) async {
      await _montar(tester);
      _asignacion.demora = Completer<void>();

      await asignar(tester);
      await tester.pumpAndSettle();
      expect(_principal, findsOneWidget);
      _asignacion.demora!.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_principal, findsOneWidget);
    });

    testWidgets('A07: la barra se ve pero no se puede tocar mientras dura la transición', (
      tester,
    ) async {
      await _montar(tester);

      await asignar(tester);
      await tester.tap(find.byKey(const Key('inicio_pestana_mapa')), warnIfMissed: false);
      await tester.pump();

      expect(find.byKey(const Key('cuenta_asignada')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(_principal, findsOneWidget);
    });

    testWidgets('A07: cerrar sesión justo en la transición no deja nada colgado', (tester) async {
      await _montar(tester);
      await asignar(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('cuenta_asignada'))),
      );

      await container.read(sesionProvider.notifier).cerrarSesion();
      await tester.pumpAndSettle();

      expect(_login, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Vista 18 — accesibilidad y texto grande', () {
    // Cada artboard con la forma de llegar a él.
    final artboards = <(String, Future<void> Function(WidgetTester))>[
      ('A01 Pendiente', (t) async => _montar(t)),
      (
        'A02 Consultando',
        (t) async {
          await _montar(t);
          _backend.demora = Completer<void>();
          await t.tap(_actualizar);
          await t.pump();
        },
      ),
      (
        'A03 Aún no asignado',
        (t) async {
          await _montar(t);
          await t.tap(_actualizar);
          await t.pumpAndSettle();
        },
      ),
      (
        'A04 Sin conexión',
        (t) async {
          await _montar(t);
          _backend.simularSinConexion = true;
          await t.tap(_actualizar);
          await t.pumpAndSettle();
        },
      ),
      (
        'A05 Error',
        (t) async {
          await _montar(t);
          _backend.falla = const ServidorException(status: 503);
          await t.tap(_actualizar);
          await t.pumpAndSettle();
        },
      ),
      ('A06 Suspendida', (t) async => _montar(t, estado: EstadoCuenta.suspendida)),
    ];

    for (final (nombre, llegar) in artboards) {
      testWidgets('$nombre: guías de accesibilidad en 390x844', (tester) async {
        final semantica = tester.ensureSemantics();
        tester.view
          ..physicalSize = const Size(390, 844)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await llegar(tester);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
        _backend.demora?.complete();
        await tester.pumpAndSettle();
      });

      testWidgets('$nombre: sin overflow con el texto al 200 % en 360x740', (tester) async {
        await llegar(tester);
        tester.view
          ..physicalSize = const Size(360, 740)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(tester.takeException(), isNull);
        // Todo se alcanza scrolleando: el último elemento (el botón) se puede tocar.
        final ultimo = find.byKey(const Key('espera_actualizar')).evaluate().isNotEmpty
            ? _actualizar
            : find.byKey(const Key('espera_ir_a_configuracion'));
        await tester.scrollUntilVisible(ultimo, 100, scrollable: _scrollable);
        expect(tester.takeException(), isNull);
        _backend.demora?.complete();
        await tester.pumpAndSettle();
      });
    }

    testWidgets('A07 al 200 % en 360x740: sin overflow y con las guías', (tester) async {
      final semantica = tester.ensureSemantics();
      tester.view
        ..physicalSize = const Size(360, 740)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _montar(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      _backend.estado = EstadoCuenta.activa;
      await tester.pumpAndSettle();
      await tester.ensureVisible(_actualizar);
      await tester.pump();
      await tester.tap(_actualizar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Ya te asignaron'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantica.dispose();
      await tester.pumpAndSettle();
    });

    testWidgets('los avisos se anuncian como región viva y los módulos dicen «Bloqueado»', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester);
      _backend.simularSinConexion = true;
      await tester.tap(_actualizar);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byKey(const Key('espera_sin_conexion'))),
        isSemantics(isLiveRegion: true),
      );
      expect(find.bySemanticsLabel(RegExp('Bloqueado')), findsNWidgets(4));
      semantica.dispose();
    });
  });
}
