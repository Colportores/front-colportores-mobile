import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

/// [RecuperacionPasswordPage] aislada (sin [ColportoresApp]) — mismo criterio que
/// `login_page_test.dart`.
///
/// El `ProviderScope` va como argumento directo de `pumpWidget`: si lo arma un helper que
/// devuelve el widget, riverpod_lint lo toma por un scope anidado
/// (`scoped_providers_should_specify_dependencies`), y acá es la raíz.
Future<void> _montarPagina(
  WidgetTester tester, {
  ThemeData? tema,
  required AuthRemoteDataSourceEnMemoria remote,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      // HU-AUTH-009 (#27): la DB local se prepara antes de la pantalla principal; acá ya está.
      dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
      authRemoteDataSourceProvider.overrideWithValue(remote),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
    ],
    child: MaterialApp(theme: tema ?? temaClaro(), home: const RecuperacionPasswordPage()),
  ),
);

const _mensajeNeutro = 'Si el email está registrado, te enviamos un enlace de recuperación';
const _textoAviso =
    'Si restablecés tu contraseña y tenés datos locales en otro dispositivo, no podrás '
    'abrirlos ahí. Tendrás que restaurar desde tu backup.';

Future<void> _completarYAceptar(
  WidgetTester tester, {
  String email = 'lucia.silva@correo.com',
}) async {
  await tester.enterText(find.byKey(const Key('recuperacion_password_email')), email);
  await _tocar(tester, 'recuperacion_password_checkbox');
  await tester.pump();
}

/// Con el texto al 200 % los botones quedan fuera de pantalla: sin esto el toque no llega.
Future<void> _tocar(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
}

OutlinedButton _reenviar(WidgetTester tester) =>
    tester.widget<OutlinedButton>(find.byKey(const Key('recuperacion_password_reenviar')));

FilledButton _enviar(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('recuperacion_password_enviar')));

/// La página dentro de un Navigator con una ruta debajo, para probar «Volver al login» y el atrás.
Future<void> _montarSobreLogin(
  WidgetTester tester, {
  required AuthRemoteDataSourceEnMemoria remote,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(remote),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('abrir_recuperacion'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const RecuperacionPasswordPage()),
                ),
                child: const Text('pantalla de abajo'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('abrir_recuperacion')));
  await tester.pumpAndSettle();
}

void main() {
  group('Vista 14 (#223) — un estado por artboard', () {
    testWidgets('A01 principal: eyebrow, título, apoyo, aviso, campo, casilla sin marcar y botón '
        'deshabilitado', (tester) async {
      await _montarPagina(tester, remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}));
      await tester.pumpAndSettle();

      expect(find.text('RECUPERAR CONTRASEÑA'), findsOneWidget);
      expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
      expect(
        find.text('Ingresá tu email y te enviamos un enlace para restablecerla.'),
        findsOneWidget,
      );
      expect(find.text(_textoAviso), findsOneWidget);
      expect(find.text('CORREO'), findsOneWidget);
      expect(find.text('Entiendo el impacto sobre mis datos locales'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('recuperacion_password_checkbox')))
            .value,
        isFalse,
      );
      expect(find.text('Enviar enlace de recuperación'), findsOneWidget);
      expect(_enviar(tester).onPressed, isNull);
    });

    testWidgets('A02 casilla marcada: el botón se habilita', (tester) async {
      await _montarPagina(tester, remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recuperacion_password_checkbox')));
      await tester.pump();

      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('recuperacion_password_checkbox')))
            .value,
        isTrue,
      );
      expect(_enviar(tester).onPressed, isNotNull);
    });

    for (final email in ['lucia', 'lucia@', 'lucia@correo', 'lu cia@correo.com']) {
      testWidgets(
        'A03 email inválido («$email»): «Revisá el email: parece incompleto.», sin enviar y '
        'con el botón habilitado',
        (tester) async {
          final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
          await _montarPagina(tester, remote: remote);
          await tester.pumpAndSettle();

          await _completarYAceptar(tester, email: email);
          await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
          await tester.pumpAndSettle();

          expect(find.text('Revisá el email: parece incompleto.'), findsOneWidget);
          expect(remote.solicitudesRecuperacionPorEmail, isEmpty);
          expect(_enviar(tester).onPressed, isNotNull);
          expect(find.byKey(const Key('recuperacion_password_exito')), findsNothing);
        },
      );
    }

    testWidgets('A03 corregir el email y volver a enviar lleva al éxito', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();
      await _completarYAceptar(tester, email: 'lucia@');
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('recuperacion_password_email')),
        'lucia@correo.com',
      );
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.text('Revisá el email: parece incompleto.'), findsNothing);
      expect(find.byKey(const Key('recuperacion_password_exito')), findsOneWidget);
    });

    testWidgets('A04 enviando: «Enviando…», campo, casilla y atrás deshabilitados', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {})
        ..demoraRecuperacion = Completer<void>();
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();
      await _completarYAceptar(tester);

      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pump();

      expect(find.text('Enviando…'), findsOneWidget);
      expect(_enviar(tester).onPressed, isNull);
      expect(
        tester.widget<TextField>(find.byKey(const Key('recuperacion_password_email'))).enabled,
        isFalse,
      );
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('recuperacion_password_checkbox')))
            .onChanged,
        isNull,
      );
      expect(
        tester.widget<IconButton>(find.byKey(const Key('recuperacion_password_atras'))).onPressed,
        isNull,
      );

      remote.demoraRecuperacion!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recuperacion_password_exito')), findsOneWidget);
    });

    testWidgets(
      'A05 éxito: pantalla aparte con el mensaje de la HU, el apoyo del spam, «Reenviar en '
      '60s» y «Volver al login»',
      (tester) async {
        final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
        await _montarPagina(tester, remote: remote);
        await tester.pumpAndSettle();
        await _completarYAceptar(tester);

        await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
        await tester.pumpAndSettle();

        expect(find.text(_mensajeNeutro), findsOneWidget);
        expect(find.text('Si no lo encontrás, revisá la carpeta de spam.'), findsOneWidget);
        expect(find.text('Reenviar en 60s'), findsOneWidget);
        expect(find.text('Volver al login'), findsOneWidget);
        expect(find.text('¿Olvidaste tu contraseña?'), findsNothing, reason: 'es otra pantalla');
        expect(find.byKey(const Key('recuperacion_password_enviar')), findsNothing);
      },
    );

    testWidgets('A05 la cuenta regresiva baja y «Reenviar enlace» vuelve a enviar y reinicia los '
        '60 s', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();
      await _completarYAceptar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      await tester.pump(const Duration(seconds: 18));
      expect(find.text('Reenviar en 42s'), findsOneWidget);

      await tester.pump(const Duration(seconds: 42));
      await tester.tap(find.byKey(const Key('recuperacion_password_reenviar')));
      await tester.pump();
      await tester.pump();

      expect(remote.solicitudesRecuperacionPorEmail['lucia.silva@correo.com'], 2);
      expect(find.text('Reenviar en 60s'), findsOneWidget);
    });

    testWidgets('A05 «Reenviar» tocado dos veces seguidas envía una sola vez', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();
      await _completarYAceptar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 60));
      remote.demoraRecuperacion = Completer<void>();

      await tester.tap(find.byKey(const Key('recuperacion_password_reenviar')));
      await tester.tap(
        find.byKey(const Key('recuperacion_password_reenviar')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(find.text('Enviando…'), findsOneWidget);
      expect(_reenviar(tester).onPressed, isNull);

      remote.demoraRecuperacion!.complete();
      await tester.pumpAndSettle();
      expect(remote.solicitudesRecuperacionPorEmail['lucia.silva@correo.com'], 2);
    });

    testWidgets('A05 si el reenvío falla por falta de conexión, lo dice en la misma pantalla y '
        'deja reintentar', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();
      await _completarYAceptar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 60));

      remote.simularSinConexion = true;
      await tester.tap(find.byKey(const Key('recuperacion_password_reenviar')));
      await tester.pumpAndSettle();

      expect(find.text('Necesitás conexión para solicitar la recuperación'), findsOneWidget);
      expect(find.byKey(const Key('recuperacion_password_exito')), findsOneWidget);
      expect(_reenviar(tester).onPressed, isNotNull);

      remote.simularSinConexion = false;
      await tester.tap(find.byKey(const Key('recuperacion_password_reenviar')));
      await tester.pumpAndSettle();
      expect(find.text('Necesitás conexión para solicitar la recuperación'), findsNothing);
      expect(find.text('Reenviar en 60s'), findsOneWidget);
    });

    testWidgets('A05 «Volver al login» y el atrás de A01 cierran la pantalla', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montarSobreLogin(tester, remote: remote);
      await _completarYAceptar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recuperacion_password_volver_login')));
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsNothing);
      expect(find.text('pantalla de abajo'), findsOneWidget);

      await tester.tap(find.byKey(const Key('abrir_recuperacion')));
      await tester.pumpAndSettle();
      expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('recuperacion_password_checkbox')))
            .value,
        isFalse,
        reason: 'al volver a entrar, nada queda marcado',
      );
      await tester.tap(find.byKey(const Key('recuperacion_password_atras')));
      await tester.pumpAndSettle();
      expect(find.byType(RecuperacionPasswordPage), findsNothing);
    });

    testWidgets('A06 sin conexión: «Necesitás conexión…» con la casilla marcada y el botón '
        'habilitado; al volver la conexión, envía', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {})
        ..simularSinConexion = true;
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();
      await _completarYAceptar(tester);

      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.text('Necesitás conexión para solicitar la recuperación'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(const Key('recuperacion_password_checkbox')))
            .value,
        isTrue,
      );
      expect(_enviar(tester).onPressed, isNotNull);

      remote.simularSinConexion = false;
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recuperacion_password_exito')), findsOneWidget);
    });

    testWidgets('el email de la sesión llega precargado y se puede cambiar', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
            authRemoteDataSourceProvider.overrideWithValue(
              AuthRemoteDataSourceEnMemoria(credenciales: const {}),
            ),
            authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            home: const RecuperacionPasswordPage(emailInicial: 'ana@example.com'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ana@example.com'), findsOneWidget);
    });
  });

  group('Vista 14 (#223) — accesibilidad y tamaños', () {
    final estados = <String, Future<void> Function(WidgetTester)>{
      'A01 principal': (tester) async {
        await _montarPagina(tester, remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}));
        await tester.pumpAndSettle();
      },
      'A02 casilla marcada': (tester) async {
        await _montarPagina(tester, remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}));
        await tester.pumpAndSettle();
        await _tocar(tester, 'recuperacion_password_checkbox');
        await tester.pump();
      },
      'A03 email inválido': (tester) async {
        await _montarPagina(tester, remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}));
        await tester.pumpAndSettle();
        await _completarYAceptar(tester, email: 'lucia@');
        await _tocar(tester, 'recuperacion_password_enviar');
        await tester.pumpAndSettle();
      },
      'A04 enviando': (tester) async {
        final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {})
          ..demoraRecuperacion = Completer<void>();
        await _montarPagina(tester, remote: remote);
        await tester.pumpAndSettle();
        await _completarYAceptar(tester);
        await _tocar(tester, 'recuperacion_password_enviar');
        await tester.pump();
      },
      'A05 éxito': (tester) async {
        await _montarPagina(tester, remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}));
        await tester.pumpAndSettle();
        await _completarYAceptar(tester);
        await _tocar(tester, 'recuperacion_password_enviar');
        await tester.pumpAndSettle();
      },
      'A05 éxito con error al reenviar': (tester) async {
        final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
        await _montarPagina(tester, remote: remote);
        await tester.pumpAndSettle();
        await _completarYAceptar(tester);
        await _tocar(tester, 'recuperacion_password_enviar');
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 60));
        remote.simularSinConexion = true;
        await _tocar(tester, 'recuperacion_password_reenviar');
        await tester.pumpAndSettle();
      },
      'A06 sin conexión': (tester) async {
        final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {})
          ..simularSinConexion = true;
        await _montarPagina(tester, remote: remote);
        await tester.pumpAndSettle();
        await _completarYAceptar(tester);
        await _tocar(tester, 'recuperacion_password_enviar');
        await tester.pumpAndSettle();
      },
    };

    for (final MapEntry(key: nombre, value: preparar) in estados.entries) {
      testWidgets('$nombre: tamaño de toque, etiquetas y contraste en 390x844', (tester) async {
        final handle = tester.ensureSemantics();
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await preparar(tester);

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });

      for (final (tam, escala) in [
        (const Size(360, 640), 1.0),
        (const Size(360, 640), 2.0),
        (const Size(412, 915), 2.0),
        (const Size(360, 740), 2.0),
      ]) {
        testWidgets('$nombre: sin overflow en ${tam.width.toInt()}x${tam.height.toInt()} con texto '
            '$escala', (tester) async {
          tester.view.physicalSize = tam;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = escala;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await preparar(tester);

          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('un email de 300 caracteres al 200 % no desborda', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _montarPagina(tester, remote: AuthRemoteDataSourceEnMemoria(credenciales: const {}));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('recuperacion_password_email')),
        '${'a' * 300}@correo.com',
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('RecuperacionPasswordPage — diseño', () {
    testWidgets('renderiza sin overflow en 390x844', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );

      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('RecuperacionPasswordPage — advertencia y casilla', () {
    testWidgets('muestra la advertencia literal de la HU antes de enviar', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recuperacion_password_aviso')), findsOneWidget);
      expect(find.text(_textoAviso), findsOneWidget);
    });

    testWidgets('el botón "Enviar" queda deshabilitado hasta marcar la casilla', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('recuperacion_password_email')),
        'lucia.silva@correo.com',
      );
      await tester.pump();

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('recuperacion_password_enviar')))
            .onPressed,
        isNull,
        reason: 'sin marcar "Entiendo el impacto..." el botón debe quedar deshabilitado',
      );

      await tester.tap(find.byKey(const Key('recuperacion_password_checkbox')));
      await tester.pump();

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('recuperacion_password_enviar')))
            .onPressed,
        isNotNull,
      );
    });
  });

  group('RecuperacionPasswordPage — envío por teclado y reentrada', () {
    testWidgets('el "Listo" del teclado envía si ya se puede (casilla marcada)', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completarYAceptar(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text(_mensajeNeutro), findsOneWidget);
      expect(remote.solicitudesRecuperacionPorEmail['lucia.silva@correo.com'], 1);
    });

    testWidgets('el "Listo" del teclado no hace nada si falta marcar la casilla', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('recuperacion_password_email')),
        'lucia.silva@correo.com',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text(_mensajeNeutro), findsNothing);
      expect(remote.solicitudesRecuperacionPorEmail, isEmpty);
    });

    testWidgets('doble tap seguido dispara una sola solicitud (guarda de reentrada)', (
      tester,
    ) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completarYAceptar(tester);

      // Dos taps seguidos sin `pump()` entre medio: simula un doble tap más rápido que el próximo
      // repintado, cuando el botón todavía no se deshabilitó visualmente.
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(remote.solicitudesRecuperacionPorEmail['lucia.silva@correo.com'], 1);
    });
  });

  group('RecuperacionPasswordPage — anti-enumeración', () {
    testWidgets('email registrado: mensaje neutro y arranca el cooldown de 60s', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completarYAceptar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recuperacion_password_exito')), findsOneWidget);
      expect(find.text(_mensajeNeutro), findsOneWidget);
      expect(remote.solicitudesRecuperacionPorEmail['lucia.silva@correo.com'], 1);
      expect(find.text('Reenviar en 60s'), findsOneWidget);
      expect(
        _reenviar(tester).onPressed,
        isNull,
        reason: 'deshabilitado mientras dura el cooldown',
      );

      await tester.pump(const Duration(seconds: 60));

      expect(find.text('Reenviar enlace'), findsOneWidget);
      expect(_reenviar(tester).onPressed, isNotNull);
    });

    testWidgets('email no registrado: el mismo mensaje neutro (no revela que no existe)', (
      tester,
    ) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completarYAceptar(tester, email: 'noexiste@correo.com');
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.text(_mensajeNeutro), findsOneWidget);
    });

    testWidgets('rate limit de Supabase (429) también se enmascara como éxito', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      )..fallaAlSolicitarRecuperacion = const ServidorException(status: 429);
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completarYAceptar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.text(_mensajeNeutro), findsOneWidget);
      expect(find.byKey(const Key('recuperacion_password_error_general')), findsNothing);
    });
  });

  group('RecuperacionPasswordPage — errores reales del servicio', () {
    testWidgets('sin conexión muestra el error, sin arrancar cooldown', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      )..simularSinConexion = true;
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completarYAceptar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recuperacion_password_error_general')), findsOneWidget);
      expect(find.byKey(const Key('recuperacion_password_exito')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('recuperacion_password_enviar')))
            .onPressed,
        isNotNull,
        reason: 'un error real no es rate limit: no debe dejar el botón en cooldown',
      );
    });

    // Era el bug #94: la página mostraba el mensaje genérico de FailureSinConexion.
    testWidgets('sin conexión muestra el texto literal de la HU-AUTH-004 (línea 822)', (
      tester,
    ) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      )..simularSinConexion = true;
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completarYAceptar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.text('Necesitás conexión para solicitar la recuperación'), findsOneWidget);
      expect(find.text('Sin conexión. Reintentá cuando tengas señal'), findsNothing);
    });

    testWidgets('falla real del servidor (no 429) muestra el mensaje traducido', (tester) async {
      final remote =
          AuthRemoteDataSourceEnMemoria(
              credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
            )
            ..fallaAlSolicitarRecuperacion = const ServidorException(
              status: 500,
              mensaje: 'El servidor no pudo procesar la solicitud',
            );
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await _completarYAceptar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.text('El servidor no pudo procesar la solicitud'), findsOneWidget);
    });

    testWidgets('email vacío: error de validación en el campo', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await _montarPagina(tester, remote: remote);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recuperacion_password_checkbox')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.text('Ingresá tu email'), findsOneWidget);
    });
  });

  group('LoginPage — enlace de recuperación', () {
    testWidgets('"¿Olvidaste tu clave?" navega a RecuperacionPasswordPage', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // HU-AUTH-009 (#27): la DB local se prepara antes de la pantalla principal; acá ya está.
            dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
            authRemoteDataSourceProvider.overrideWithValue(
              AuthRemoteDataSourceEnMemoria(credenciales: const {}),
            ),
            authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
          ],
          child: MaterialApp(theme: temaClaro(), home: const LoginPage(mostrarApple: false)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('login_olvidaste_clave')));
      await tester.pumpAndSettle();

      expect(find.byType(RecuperacionPasswordPage), findsOneWidget);
    });
  });
}
