import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/recuperacion_password_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// [RecuperacionPasswordPage] aislada (sin [ColportoresApp]) — mismo criterio que
/// `verificacion_email_page_test.dart`.
Widget _pagina({ThemeData? tema, required AuthRemoteDataSourceEnMemoria remote}) => ProviderScope(
  overrides: [
    authRemoteDataSourceProvider.overrideWithValue(remote),
    authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
  ],
  child: MaterialApp(theme: tema ?? temaClaro(), home: const RecuperacionPasswordPage()),
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
  await tester.tap(find.byKey(const Key('recuperacion_password_checkbox')));
  await tester.pump();
}

void main() {
  group('RecuperacionPasswordPage — diseño', () {
    testWidgets('renderiza sin overflow en 390x844 (claro y oscuro)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );

      await tester.pumpWidget(_pagina(tema: temaClaro(), remote: remote));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_pagina(tema: temaOscuro(), remote: remote));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('RecuperacionPasswordPage — advertencia y casilla', () {
    testWidgets('muestra la advertencia literal de la HU antes de enviar', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await tester.pumpWidget(_pagina(remote: remote));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recuperacion_password_aviso')), findsOneWidget);
      expect(find.text(_textoAviso), findsOneWidget);
    });

    testWidgets('el botón "Enviar" queda deshabilitado hasta marcar la casilla', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await tester.pumpWidget(_pagina(remote: remote));
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

  group('RecuperacionPasswordPage — anti-enumeración', () {
    testWidgets('email registrado: mensaje neutro y arranca el cooldown de 60s', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
      );
      await tester.pumpWidget(_pagina(remote: remote));
      await tester.pumpAndSettle();

      await _completarYAceptar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recuperacion_password_exito')), findsOneWidget);
      expect(find.text(_mensajeNeutro), findsOneWidget);
      expect(remote.solicitudesRecuperacionPorEmail['lucia.silva@correo.com'], 1);
      expect(find.text('Reenviar en 60s'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('recuperacion_password_enviar')))
            .onPressed,
        isNull,
        reason: 'deshabilitado mientras dura el cooldown',
      );

      await tester.pump(const Duration(seconds: 60));

      expect(find.text('Enviar enlace de recuperación'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('recuperacion_password_enviar')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('email no registrado: el mismo mensaje neutro (no revela que no existe)', (
      tester,
    ) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await tester.pumpWidget(_pagina(remote: remote));
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
      await tester.pumpWidget(_pagina(remote: remote));
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
      await tester.pumpWidget(_pagina(remote: remote));
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

    testWidgets('falla real del servidor (no 429) muestra el mensaje traducido', (tester) async {
      final remote =
          AuthRemoteDataSourceEnMemoria(
              credenciales: const {'lucia.silva@correo.com': 'Secreto123'},
            )
            ..fallaAlSolicitarRecuperacion = const ServidorException(
              status: 500,
              mensaje: 'El servidor no pudo procesar la solicitud',
            );
      await tester.pumpWidget(_pagina(remote: remote));
      await tester.pumpAndSettle();

      await _completarYAceptar(tester);
      await tester.tap(find.byKey(const Key('recuperacion_password_enviar')));
      await tester.pumpAndSettle();

      expect(find.text('El servidor no pudo procesar la solicitud'), findsOneWidget);
    });

    testWidgets('email vacío: error de validación en el campo', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await tester.pumpWidget(_pagina(remote: remote));
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
