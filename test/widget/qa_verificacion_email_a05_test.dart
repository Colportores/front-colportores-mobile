// QA de la vista 12, artboard A05 «Ya verificado» (front-colportores-mobile#279, que sigue a
// #242 y al PR #271): la pantalla NO sale sola —decisión de Cristian del 02/10, WCAG 2.2.1: sin
// cuenta regresiva ni barra de avance—; dice «Ya podés entrar a tu inicio.» con o sin sesión, y el
// botón dice a dónde va de verdad: «Ir a mi inicio» (con sesión) o «Ir al login» (sin sesión).
// Complementa a `enlace_verificacion_usado_test.dart` con los casos límite que ese archivo no
// toca: la sesión que termina y vuelve, el arranque en frío con sesión guardada, el atrás del
// sistema y el segundo toque en la app entera, el ciclo de vida, y las guías de accesibilidad de
// la variante con sesión.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/verificacion_email_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _correo = 'lucia.silva@correo.com';
const _clave = 'Secreto123';

const _titulo = 'Tu email ya está verificado';
const _texto = 'Ya podés entrar a tu inicio.';
const _botonConSesion = 'Ir a mi inicio';
const _botonSinSesion = 'Ir al login';

final _botonSalir = find.byKey(const Key('verificacion_email_ir_login'));
final _inicio = find.byKey(const Key('inicio_principal'));
final _login = find.byKey(const Key('login_enviar'));

Future<AuthRemoteDataSourceEnMemoria> _remotoConfirmado() async {
  final remote = AuthRemoteDataSourceEnMemoria(
    credenciales: const {},
    requiereVerificacionAlRegistrar: true,
  );
  await remote.registrar(
    nombre: 'Lucía',
    apellido: 'Silva',
    cedula: '12345678',
    email: _correo,
    password: _clave,
  );
  remote.confirmarEmail(_correo);
  return remote;
}

/// El `ProviderScope` va como argumento directo de `pumpWidget` (ver `app_test.dart`).
Future<void> _montarApp(
  WidgetTester tester,
  AuthRemoteDataSourceEnMemoria remote, {
  AuthLocalDataSourceEnMemoria? local,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(remote),
      authLocalDataSourceProvider.overrideWithValue(local ?? AuthLocalDataSourceEnMemoria()),
    ],
    child: const ColportoresApp(),
  ),
);

void _pantalla(WidgetTester tester, [Size tamanio = const Size(390, 844), double escala = 1]) {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

ProviderContainer _contenedor(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ColportoresApp)));

/// La app entera con la sesión abierta y el enlace de verificación ya usado recién llegado: 12-A05
/// con sesión (caso 1 de HU-AUTH-002).
Future<AuthRemoteDataSourceEnMemoria> _a05ConSesion(
  WidgetTester tester, {
  Size tamanio = const Size(390, 844),
  double escala = 1,
}) async {
  // Se entra con la vista de referencia (a 2.0 el botón del login queda fuera de pantalla) y recién
  // después se pasa al tamaño y la escala que se quieren medir.
  _pantalla(tester);
  final remote = await _remotoConfirmado();
  await _montarApp(tester, remote);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('login_email')), _correo);
  await tester.enterText(find.byKey(const Key('login_password')), _clave);
  await tester.tap(find.byKey(const Key('login_enviar')));
  await tester.pumpAndSettle();
  expect(_inicio, findsOneWidget);
  _pantalla(tester, tamanio, escala);
  remote.simularEnlaceVerificacionInvalido();
  await tester.pumpAndSettle();
  expect(find.text(_titulo), findsOneWidget);
  return remote;
}

/// La pantalla sola, con o sin sesión abierta en un contenedor propio.
Future<void> _a05Sola(
  WidgetTester tester, {
  required bool conSesion,
  Size tamanio = const Size(390, 844),
  double escala = 1,
}) async {
  _pantalla(tester, tamanio, escala);
  final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {_correo: _clave});
  final container = ProviderContainer(
    overrides: [
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(remote),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  if (conSesion) {
    await container.read(sesionProvider.notifier).iniciarSesion(email: _correo, password: _clave);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: temaClaro(),
        home: const VerificacionEmailPage(
          email: _correo,
          estadoInicial: EstadoVerificacionEmail.yaVerificado,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('QA 12-A05 (02/10) — criterios de aceptación: mismo texto, el botón sigue a la sesión', () {
    testWidgets(
      'caso 1, sesión activa: texto fijo y botón «inicio», sin barra ni cuenta regresiva ni correo',
      (tester) async {
        await _a05ConSesion(tester);

        expect(find.text(_titulo), findsOneWidget);
        expect(find.text(_texto), findsOneWidget);
        expect(find.text(_botonConSesion), findsOneWidget);
        expect(find.text(_botonSinSesion), findsNothing);
        // Sin salida automática: ni el texto de la cuenta regresiva ni la barra de avance.
        expect(find.textContaining('Te llevamos'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('El enlace expiró'), findsNothing);
        expect(find.text('VERIFICACIÓN DE EMAIL'), findsNothing);
        expect(find.byKey(const Key('verificacion_email_reenviar')), findsNothing);
        // Privacidad: la pantalla de cierre no muestra ni repite el correo.
        expect(find.textContaining(_correo), findsNothing);
        expect(find.textContaining('@'), findsNothing);
      },
    );

    testWidgets('caso 2, login en silencio: con la sesión abierta por el login dice «inicio»', (
      tester,
    ) async {
      _pantalla(tester);
      final remote = await _remotoConfirmado();
      await _montarApp(tester, remote);
      await tester.pumpAndSettle();
      unawaited(
        navigatorKeyColportores.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const VerificacionEmailPage(email: _correo, password: _clave),
          ),
        ),
      );
      await tester.pumpAndSettle();

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();

      expect(remote.llamadasIniciarSesion, 1);
      expect(find.text(_titulo), findsOneWidget);
      expect(find.text(_texto), findsOneWidget);
      expect(find.text(_botonConSesion), findsOneWidget);
      expect(find.text(_botonSinSesion), findsNothing);
      expect(find.textContaining(_correo), findsNothing);
    });

    testWidgets('sin sesión: el mismo texto, «Ir al login» como botón y nada que cuente', (
      tester,
    ) async {
      await _a05Sola(tester, conSesion: false);

      expect(find.text(_titulo), findsOneWidget);
      expect(find.text(_texto), findsOneWidget);
      expect(find.text(_botonSinSesion), findsOneWidget);
      expect(find.text(_botonConSesion), findsNothing);
      expect(find.textContaining('Te llevamos'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('el botón de cada variante tiene su nombre accesible y el título no se pierde', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      try {
        await _a05Sola(tester, conSesion: true);
        expect(find.bySemanticsLabel(_botonConSesion), findsOneWidget);
        expect(find.bySemanticsLabel(_botonSinSesion), findsNothing);
        expect(find.bySemanticsLabel(_texto), findsOneWidget);
        expect(find.bySemanticsLabel(_titulo), findsOneWidget);

        await _a05Sola(tester, conSesion: false);
        expect(find.bySemanticsLabel(_botonSinSesion), findsOneWidget);
        expect(find.bySemanticsLabel(_botonConSesion), findsNothing);
        expect(find.bySemanticsLabel(_texto), findsOneWidget);
      } finally {
        semantica.dispose();
      }
    });

    testWidgets('arranque en frío con la sesión guardada: el botón dice «inicio», no «login»', (
      tester,
    ) async {
      _pantalla(tester);
      final remote = await _remotoConfirmado();
      final sesion = await remote.iniciarSesion(email: _correo, password: _clave);
      final local = AuthLocalDataSourceEnMemoria();
      await local.guardarSesion(sesion);
      await _montarApp(tester, remote, local: local);
      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();

      expect(find.text(_titulo), findsOneWidget);
      expect(find.text(_texto), findsOneWidget);
      expect(find.text(_botonConSesion), findsOneWidget);
      expect(find.text(_botonSinSesion), findsNothing);
    });
  });

  group('QA 12-A05 (02/10) — no sale sola y casos límite con la app entera', () {
    testWidgets('con sesión: pasado un minuto la pantalla sigue ahí hasta que se toca el botón', (
      tester,
    ) async {
      await _a05ConSesion(tester);

      for (final segundos in [3, 5, 20, 60]) {
        await tester.pump(Duration(seconds: segundos));
        expect(find.text(_titulo), findsOneWidget, reason: 'a los $segundos s más');
        expect(_inicio, findsNothing);
      }
      expect(tester.takeException(), isNull);

      await tester.tap(_botonSalir);
      await tester.pumpAndSettle();
      expect(find.text(_titulo), findsNothing);
      expect(_inicio, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Ir a mi inicio» dos veces seguidas: sale una sola vez y sin errores', (
      tester,
    ) async {
      await _a05ConSesion(tester);

      final onPressed = tester.widget<FilledButton>(_botonSalir).onPressed!;
      onPressed();
      onPressed();
      await tester.pumpAndSettle();
      expect(_inicio, findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      expect(_inicio, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el atrás del sistema con sesión vuelve a Inicio y no deja nada pendiente', (
      tester,
    ) async {
      await _a05ConSesion(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(_titulo), findsNothing);
      expect(_inicio, findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      expect(_inicio, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('si la sesión termina con la pantalla abierta, el botón pasa a «Ir al login»', (
      tester,
    ) async {
      await _a05ConSesion(tester);

      await _contenedor(tester).read(sesionProvider.notifier).cerrarSesion();
      await tester.pump();
      expect(find.text(_texto), findsOneWidget);
      expect(find.text(_botonSinSesion), findsOneWidget);
      expect(find.text(_botonConSesion), findsNothing);

      // Tampoco sale sola cuando la sesión termina.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text(_titulo), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('si la sesión termina, «Ir al login» lleva al login y no a Inicio', (tester) async {
      await _a05ConSesion(tester);

      await _contenedor(tester).read(sesionProvider.notifier).cerrarSesion();
      await tester.pump();
      await tester.tap(_botonSalir);
      await tester.pumpAndSettle();

      expect(_login, findsOneWidget);
      expect(_inicio, findsNothing);
    });

    testWidgets('la sesión se cierra y se vuelve a abrir: el texto no cambia y el botón sigue', (
      tester,
    ) async {
      await _a05ConSesion(tester);
      final notifier = _contenedor(tester).read(sesionProvider.notifier);

      await notifier.cerrarSesion();
      await tester.pump();
      expect(find.text(_texto), findsOneWidget);
      expect(find.text(_botonSinSesion), findsOneWidget);

      await notifier.iniciarSesion(email: _correo, password: _clave);
      await tester.pump();
      expect(find.text(_texto), findsOneWidget);
      expect(find.text(_botonConSesion), findsOneWidget);
      expect(find.text(_botonSinSesion), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pasar la app a segundo plano y volver: la pantalla sigue ahí, sin salir sola', (
      tester,
    ) async {
      await _a05ConSesion(tester);

      // Las transiciones válidas del ciclo de vida: resumed → inactive → hidden → paused y vuelta.
      for (final estado in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(estado);
      }
      await tester.pump(const Duration(seconds: 30));
      for (final estado in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(estado);
      }
      await tester.pump();
      expect(find.text(_texto), findsOneWidget);

      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text(_titulo), findsOneWidget);
      expect(_inicio, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un enlace usado más tarde vuelve a mostrar A05, y tampoco sale solo', (
      tester,
    ) async {
      final remote = await _a05ConSesion(tester);
      await tester.tap(_botonSalir);
      await tester.pumpAndSettle();
      expect(_inicio, findsOneWidget);

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();
      expect(find.text(_texto), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      expect(find.text(_titulo), findsOneWidget);

      await tester.tap(_botonSalir);
      await tester.pumpAndSettle();
      expect(find.text(_titulo), findsNothing);
      expect(_inicio, findsOneWidget);
    });

    testWidgets('otro enlace usado con la pantalla abierta no apila una segunda A05', (
      tester,
    ) async {
      final remote = await _a05ConSesion(tester);

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();
      expect(find.text(_titulo), findsOneWidget);

      await tester.tap(_botonSalir);
      await tester.pumpAndSettle();
      expect(find.text(_titulo), findsNothing);
      expect(_inicio, findsOneWidget);
    });
  });

  group('QA 12-A05 (02/10) — accesibilidad y tamaños de la variante con sesión', () {
    for (final MapEntry(key: nombre, value: tam) in const {
      '360x640': Size(360, 640),
      '412x915': Size(412, 915),
    }.entries) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('con sesión en $nombre, texto $escala: sin overflow y accesible', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          try {
            await _a05Sola(tester, conSesion: true, tamanio: tam, escala: escala);

            expect(tester.takeException(), isNull);
            await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
            await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
            await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
            await expectLater(tester, meetsGuideline(textContrastGuideline));
          } finally {
            semantica.dispose();
          }
        });
      }
    }

    testWidgets('con sesión, 360x640 y texto 2.0: «Ir a mi inicio» se alcanza y se puede tocar', (
      tester,
    ) async {
      await _a05ConSesion(tester, tamanio: const Size(360, 640), escala: 2);

      await tester.ensureVisible(_botonSalir);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(_botonSalir);
      await tester.pumpAndSettle();

      expect(_inicio, findsOneWidget);
    });

    testWidgets('con sesión y texto 2.0 la etiqueta del botón no queda cortada por la píldora', (
      tester,
    ) async {
      await _a05Sola(tester, conSesion: true, tamanio: const Size(360, 640), escala: 2);

      await tester.ensureVisible(_botonSalir);
      await tester.pump();
      final boton = tester.getRect(_botonSalir);
      final etiqueta = tester.getRect(
        find.descendant(of: _botonSalir, matching: find.text(_botonConSesion)),
      );
      expect(etiqueta.left, greaterThanOrEqualTo(boton.left));
      expect(etiqueta.right, lessThanOrEqualTo(boton.right));
      expect(etiqueta.top, greaterThanOrEqualTo(boton.top));
      expect(etiqueta.bottom, lessThanOrEqualTo(boton.bottom));
    });
  });
}
