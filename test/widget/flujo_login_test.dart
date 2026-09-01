import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({required AuthRemoteDataSourceEnMemoria remote}) => ProviderScope(
  overrides: [
    authRemoteDataSourceProvider.overrideWithValue(remote),
    authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
  ],
  child: const ColportoresApp(),
);

AuthRemoteDataSourceEnMemoria _remote() =>
    AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'});

void main() {
  group('Flujo de login', () {
    testWidgets('cuando no hay sesión, arranca en la pantalla de login', (tester) async {
      await tester.pumpWidget(_app(remote: _remote()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_enviar')), findsOneWidget);
    });

    testWidgets('cuando el email es inválido, muestra el error en el campo', (tester) async {
      await tester.pumpWidget(_app(remote: _remote()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('login_email')), 'no-es-email');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.tap(find.byKey(const Key('login_enviar')));
      await tester.pumpAndSettle();

      expect(find.text('El email no es válido'), findsOneWidget);
      expect(find.byKey(const Key('login_error_general')), findsNothing);
    });

    testWidgets('cuando las credenciales son incorrectas, muestra el error general', (
      tester,
    ) async {
      await tester.pumpWidget(_app(remote: _remote()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'incorrecta1');
      await tester.tap(find.byKey(const Key('login_enviar')));
      await tester.pumpAndSettle();

      expect(find.text('Email o contraseña incorrectos'), findsOneWidget);
      expect(find.byKey(const Key('inicio_email')), findsNothing);
    });

    testWidgets('cuando no hay conexión, avisa sin exponer detalles', (tester) async {
      final remote = _remote()..simularSinConexion = true;
      await tester.pumpWidget(_app(remote: remote));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.tap(find.byKey(const Key('login_enviar')));
      await tester.pumpAndSettle();

      expect(find.text('Sin conexión. Reintentá cuando tengas señal'), findsOneWidget);
    });

    testWidgets('cuando las credenciales son válidas, entra y puede cerrar sesión', (tester) async {
      await tester.pumpWidget(_app(remote: _remote()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('login_email')), 'Ana@Example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.tap(find.byKey(const Key('login_enviar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inicio_email')), findsOneWidget);
      expect(find.text('ana@example.com'), findsOneWidget);

      await tester.tap(find.byKey(const Key('inicio_cerrar_sesion')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_enviar')), findsOneWidget);
    });
  });
}
