// QA de la vista 14 (#223, HU-AUTH-004): casos límite de entrada y navegación que
// `recuperacion_password_page_test.dart` no cubre: formatos de email, lo tipeado tras un error,
// el atrás del sistema mientras se envía y un email más largo que el máximo de un email real.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _mensajeNeutro = 'Si el email está registrado, te enviamos un enlace de recuperación';
const _incompleto = 'Revisá el email: parece incompleto.';
const _sinConexion = 'Necesitás conexión para solicitar la recuperación';

Finder _k(String key) => find.byKey(Key(key));

/// La pantalla abierta desde otra ruta (como desde el login), para poder salir y volver.
Future<void> _montar(WidgetTester tester, AuthRemoteDataSourceEnMemoria remote) async {
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
          builder: (c) => TextButton(
            key: const Key('abrir'),
            onPressed: () => Navigator.of(
              c,
            ).push<void>(MaterialPageRoute<void>(builder: (_) => const RecuperacionPasswordPage())),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(_k('abrir'));
  await tester.pumpAndSettle();
}

Future<void> _tocar(WidgetTester tester, String key) async {
  await tester.ensureVisible(_k(key));
  await tester.tap(_k(key));
  await tester.pumpAndSettle();
}

Future<void> _enviarCon(WidgetTester tester, String email) async {
  await tester.enterText(_k('recuperacion_password_email'), email);
  await _tocar(tester, 'recuperacion_password_checkbox');
  await _tocar(tester, 'recuperacion_password_enviar');
}

bool _marcada(WidgetTester tester) =>
    tester.widget<CheckboxListTile>(_k('recuperacion_password_checkbox')).value ?? false;

void main() {
  late AuthRemoteDataSourceEnMemoria remote;
  setUp(() => remote = AuthRemoteDataSourceEnMemoria(credenciales: const {}));

  group('QA vista 14 — validación del email', () {
    for (final email in ['lucia+cobros@correo.com', '  lucia@correo.com  ', 'LUCIA@CORREO.COM']) {
      testWidgets('«$email» es válido y lleva al éxito neutro', (tester) async {
        await _montar(tester, remote);
        await _enviarCon(tester, email);
        expect(find.text(_mensajeNeutro), findsOneWidget);
      });
    }

    for (final email in [
      'lucia@@correo.com',
      'lucia@correo.c',
      '@correo.com',
      'lucia correo.com',
    ]) {
      testWidgets('«$email» muestra A03 y no envía', (tester) async {
        await _montar(tester, remote);
        await _enviarCon(tester, email);
        expect(find.text(_incompleto), findsOneWidget);
        expect(find.text(_mensajeNeutro), findsNothing);
      });
    }

    testWidgets('solo espacios: pide el email, no dice «parece incompleto»', (tester) async {
      await _montar(tester, remote);
      await _enviarCon(tester, '     ');
      expect(find.text('Ingresá tu email'), findsOneWidget);
      expect(find.text(_incompleto), findsNothing);
    });

    testWidgets('después de A03 lo tipeado y la casilla siguen y el botón queda habilitado', (
      tester,
    ) async {
      await _montar(tester, remote);
      await _enviarCon(tester, 'lucia@');
      expect(find.text('lucia@'), findsOneWidget);
      expect(_marcada(tester), isTrue);
      expect(tester.widget<FilledButton>(_k('recuperacion_password_enviar')).onPressed, isNotNull);
    });

    testWidgets('después de A06 lo tipeado y la casilla siguen y reintentar lleva al éxito', (
      tester,
    ) async {
      remote.simularSinConexion = true;
      await _montar(tester, remote);
      await _enviarCon(tester, 'lucia@correo.com');
      expect(find.text(_sinConexion), findsOneWidget);
      expect(find.text('lucia@correo.com'), findsOneWidget);
      expect(_marcada(tester), isTrue);

      remote.simularSinConexion = false;
      await _tocar(tester, 'recuperacion_password_enviar');
      expect(find.text(_mensajeNeutro), findsOneWidget);
      expect(find.text(_sinConexion), findsNothing);
    });

    testWidgets('un email de 300 caracteres no es un email: A03 en vez de mandarlo', (
      tester,
    ) async {
      await _montar(tester, remote);
      await _enviarCon(tester, '${'a' * 290}@correo.com');
      expect(find.text(_mensajeNeutro), findsNothing);
    });
  });

  group('QA vista 14 — navegación', () {
    testWidgets('el atrás del sistema mientras envía no saca de la pantalla, como la flecha', (
      tester,
    ) async {
      remote.demoraRecuperacion = Completer<void>();
      await _montar(tester, remote);
      await tester.enterText(_k('recuperacion_password_email'), 'lucia@correo.com');
      await _tocar(tester, 'recuperacion_password_checkbox');
      await tester.tap(_k('recuperacion_password_enviar'));
      await tester.pump();
      expect(tester.widget<IconButton>(_k('recuperacion_password_atras')).onPressed, isNull);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(RecuperacionPasswordPage), findsOneWidget);
      remote.demoraRecuperacion!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('salir y volver a entrar: formulario limpio, casilla sin marcar y botón apagado', (
      tester,
    ) async {
      await _montar(tester, remote);
      await _enviarCon(tester, 'lucia@correo.com');
      await _tocar(tester, 'recuperacion_password_volver_login');
      await tester.tap(_k('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('¿Olvidaste tu contraseña?'), findsOneWidget);
      expect(_marcada(tester), isFalse);
      expect(tester.widget<FilledButton>(_k('recuperacion_password_enviar')).onPressed, isNull);
    });
  });
}
