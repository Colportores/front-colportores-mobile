import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Envoltorio de test: agrega una demora real antes de delegar al fake en memoria, para poder
/// observar el estado "cargando" de la UI (con el fake sin demora, la Future ya resuelve dentro
/// del mismo pump y no hay forma de atrapar el estado intermedio).
class _RemoteConDemora implements AuthRemoteDataSource {
  _RemoteConDemora(this._interno);

  final AuthRemoteDataSourceEnMemoria _interno;

  @override
  Future<SesionModel> iniciarSesion({required String email, required String password}) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return _interno.iniciarSesion(email: email, password: password);
  }

  @override
  Future<SesionModel> registrar({
    required String nombre,
    required String apellido,
    required String cedula,
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return _interno.registrar(
      nombre: nombre,
      apellido: apellido,
      cedula: cedula,
      email: email,
      password: password,
    );
  }

  @override
  Future<SesionModel> iniciarSesionConGoogle() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return _interno.iniciarSesionConGoogle();
  }

  @override
  Future<SesionModel?> obtenerSesionActual() => _interno.obtenerSesionActual();

  @override
  Future<void> cerrarSesion(String accessToken) => _interno.cerrarSesion(accessToken);
}

/// [LoginPage] aislada (sin [ColportoresApp]): estas pruebas cubren diseño/tema/proveedores, no el
/// flujo de negocio — eso ya está en `flujo_login_test.dart`.
Widget _pagina({ThemeData? tema, bool? mostrarApple}) => ProviderScope(
  overrides: [
    authRemoteDataSourceProvider.overrideWithValue(
      AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
    ),
    authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
  ],
  child: MaterialApp(
    theme: tema ?? temaClaro(),
    home: LoginPage(mostrarApple: mostrarApple),
  ),
);

void main() {
  group('LoginPage — diseño', () {
    testWidgets('renderiza con tema claro sin overflow en 390x844', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_pagina(tema: temaClaro()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('renderiza con tema oscuro sin overflow en 390x844', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_pagina(tema: temaOscuro()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('el botón de Apple solo aparece cuando mostrarApple es true', (tester) async {
      await tester.pumpWidget(_pagina(mostrarApple: true));
      await tester.pumpAndSettle();
      expect(find.text('Continuar con Apple'), findsOneWidget);

      await tester.pumpWidget(_pagina(mostrarApple: false));
      await tester.pumpAndSettle();
      expect(find.text('Continuar con Apple'), findsNothing);
    });

    testWidgets('tocar "Continuar con Google" inicia sesión con el proveedor', (tester) async {
      await tester.pumpWidget(_pagina());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continuar con Google'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(tester.element(find.byType(LoginPage)));
      expect(
        container.read(sesionProvider).value?.email,
        AuthRemoteDataSourceEnMemoria.emailGoogle,
      );
      expect(find.text('Disponible próximamente'), findsNothing);
    });

    testWidgets('si Google falla, muestra el mensaje del Failure', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRemoteDataSourceProvider.overrideWithValue(
              AuthRemoteDataSourceEnMemoria(credenciales: const {}, simularSinConexion: true),
            ),
            authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
          ],
          child: MaterialApp(theme: temaClaro(), home: const LoginPage(mostrarApple: false)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continuar con Google'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Sin conexión'), findsOneWidget);
    });

    testWidgets('Entrar se deshabilita y muestra spinner mientras iniciarSesion no resolvió', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRemoteDataSourceProvider.overrideWithValue(
              _RemoteConDemora(
                AuthRemoteDataSourceEnMemoria(
                  credenciales: const {'ana@example.com': 'secreto123'},
                ),
              ),
            ),
            authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
          ],
          child: MaterialApp(theme: temaClaro(), home: const LoginPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.tap(find.byKey(const Key('login_enviar')));
      await tester.pump(); // un solo frame: captura el estado intermedio, no lo resuelve

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Entrar'), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(const Key('login_enviar'))).onPressed, isNull);

      await tester.pumpAndSettle();
    });
  });
}
