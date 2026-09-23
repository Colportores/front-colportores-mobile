import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Remoto que lanza una excepción fija en `iniciarSesion` — para ver el banner de "email sin
/// confirmar" sin depender de Supabase real (eso ya lo cubre el test unitario del data source).
final class _RemoteQueLanzaAlIniciar implements AuthRemoteDataSource {
  _RemoteQueLanzaAlIniciar(this.excepcion);

  final AuthRemoteException excepcion;

  @override
  Future<SesionModel> iniciarSesion({required String email, required String password}) async =>
      throw excepcion;

  @override
  Future<SesionModel?> registrar({
    required String nombre,
    required String apellido,
    required String cedula,
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<SesionModel> iniciarSesionConGoogle() => throw UnimplementedError();

  @override
  Future<SesionModel?> obtenerSesionActual() async => null;

  @override
  Future<void> cerrarSesion(String accessToken) => throw UnimplementedError();

  @override
  Future<void> reenviarVerificacion(String email) => throw UnimplementedError();

  @override
  Stream<void> get erroresVerificacionEmail => const Stream.empty();
}

Widget _app({required AuthRemoteDataSource remote}) => ProviderScope(
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

    testWidgets('cuando el email no está confirmado, muestra el aviso de verificar', (
      tester,
    ) async {
      final remote = _RemoteQueLanzaAlIniciar(
        const ServidorException(
          mensaje: 'Tenés que verificar tu correo antes de entrar. Revisá tu bandeja.',
        ),
      );
      await tester.pumpWidget(_app(remote: remote));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.tap(find.byKey(const Key('login_enviar')));
      await tester.pumpAndSettle();

      expect(find.textContaining('verificar tu correo'), findsOneWidget);
    });

    testWidgets('cuando el registro requiere verificar el email, lleva a la pantalla de '
        'verificación pendiente, y "Ya verifiqué mi email" entra tras confirmar', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {},
        requiereVerificacionAlRegistrar: true,
      );
      await tester.pumpWidget(_app(remote: remote));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('login_ir_a_registro')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('registro_nombre')), 'Lucía');
      await tester.enterText(find.byKey(const Key('registro_apellido')), 'Silva');
      await tester.enterText(find.byKey(const Key('registro_cedula')), '4812309-2');
      await tester.enterText(find.byKey(const Key('registro_email')), 'lucia.silva@correo.com');
      await tester.enterText(find.byKey(const Key('registro_password')), 'Secreto123');
      await tester.tap(find.byKey(const Key('registro_terminos')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('registro_continuar')));
      await tester.pumpAndSettle();

      // No volvió al login ni entró directo: pasó a la pantalla de verificación pendiente.
      expect(find.byKey(const Key('login_enviar')), findsNothing);
      expect(find.byKey(const Key('inicio_email')), findsNothing);
      expect(find.textContaining('lucia.silva@correo.com'), findsWidgets);
      expect(find.byKey(const Key('verificacion_email_ya_verifique')), findsOneWidget);

      // Simula que confirmó el correo (tocó el enlace) y toca "Ya verifiqué mi email".
      remote.confirmarEmail('lucia.silva@correo.com');
      await tester.tap(find.byKey(const Key('verificacion_email_ya_verifique')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('verificacion_email_continuar')), findsOneWidget);
      await tester.tap(find.byKey(const Key('verificacion_email_continuar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inicio_email')), findsOneWidget);
      expect(find.text('lucia.silva@correo.com'), findsOneWidget);
    });
  });
}
