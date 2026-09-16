import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/login_page.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/registro_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// [RegistroPage] aislada (sin [ColportoresApp]): igual criterio que `login_page_test.dart` —
/// cubre diseño/tema/validación/proveedores. El caso feliz necesita, además, una pantalla debajo
/// en la pila para poder comprobar que `popUntil((r) => r.isFirst)` cierra el registro.
Widget _pagina({ThemeData? tema, bool? mostrarApple, AuthRemoteDataSourceEnMemoria? remote}) =>
    ProviderScope(
      overrides: [
        authRemoteDataSourceProvider.overrideWithValue(
          remote ??
              AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      ],
      child: MaterialApp(
        theme: tema ?? temaClaro(),
        home: RegistroPage(mostrarApple: mostrarApple),
      ),
    );

/// Arranca en una pantalla inicial cualquiera y empuja [RegistroPage] arriba, para poder
/// verificar que el éxito hace `pop` hasta volver a ella.
Widget _pilaConPantallaInicial({required AuthRemoteDataSourceEnMemoria remote}) => ProviderScope(
  overrides: [
    authRemoteDataSourceProvider.overrideWithValue(remote),
    authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
  ],
  child: MaterialApp(
    theme: temaClaro(),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const Key('abrir_registro'),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const RegistroPage())),
            child: const Text('abrir registro'),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _completarFormulario(
  WidgetTester tester, {
  String email = 'lucia.silva@correo.com',
  String password = 'Secreto123',
}) async {
  await tester.enterText(find.byKey(const Key('registro_nombre')), 'Lucía');
  await tester.enterText(find.byKey(const Key('registro_apellido')), 'Silva');
  await tester.enterText(find.byKey(const Key('registro_cedula')), '4812309-2');
  await tester.enterText(find.byKey(const Key('registro_email')), email);
  await tester.enterText(find.byKey(const Key('registro_password')), password);
  await tester.tap(find.byKey(const Key('registro_terminos')));
  await tester.pump();
}

void main() {
  group('RegistroPage — diseño', () {
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
      expect(find.text('Apple'), findsOneWidget);

      await tester.pumpWidget(_pagina(mostrarApple: false));
      await tester.pumpAndSettle();
      expect(find.text('Apple'), findsNothing);
    });
  });

  group('RegistroPage — validación', () {
    testWidgets('enviar vacío muestra errores por campo y no llama al notifier', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'ana@example.com': 'secreto123'},
      );
      await tester.pumpWidget(_pagina(remote: remote));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('registro_continuar')));
      await tester.pumpAndSettle();

      expect(find.text('Ingresá tu nombre'), findsOneWidget);
      expect(find.text('Ingresá tu apellido'), findsOneWidget);
      expect(find.text('Ingresá tu cédula'), findsOneWidget);
      expect(find.text('Ingresá tu email'), findsOneWidget);
      expect(find.text('Ingresá tu contraseña'), findsOneWidget);
      expect(find.text('Tenés que aceptar los términos.'), findsOneWidget);
      expect(remote.usuariosRegistrados, isEmpty);
    });
  });

  group('RegistroPage — flujo', () {
    testWidgets('caso feliz: registra, deja la sesión iniciada y cierra la página', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'ana@example.com': 'secreto123'},
      );
      await tester.pumpWidget(_pilaConPantallaInicial(remote: remote));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('abrir_registro')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('registro_continuar')), findsOneWidget);

      await _completarFormulario(tester);
      await tester.tap(find.byKey(const Key('registro_continuar')));
      await tester.pumpAndSettle();

      // Cerró el registro y volvió a la pantalla inicial.
      expect(find.byKey(const Key('registro_continuar')), findsNothing);
      expect(find.byKey(const Key('abrir_registro')), findsOneWidget);
      expect(find.text('Cuenta creada'), findsOneWidget);
      expect(remote.usuariosRegistrados.containsKey('lucia.silva@correo.com'), isTrue);
    });

    testWidgets('email ya registrado muestra el banner general', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'ana@example.com': 'secreto123'},
      );
      await tester.pumpWidget(_pagina(remote: remote));
      await tester.pumpAndSettle();

      await _completarFormulario(tester, email: 'ana@example.com');
      await tester.tap(find.byKey(const Key('registro_continuar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('registro_error_general')), findsOneWidget);
      expect(find.text('Ya existe una cuenta con ese correo.'), findsOneWidget);
    });
  });

  group('Desde el login', () {
    testWidgets('"Registrate" abre RegistroPage', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRemoteDataSourceProvider.overrideWithValue(
              AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
            ),
            authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
          ],
          child: MaterialApp(theme: temaClaro(), home: const LoginPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('login_ir_a_registro')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('registro_continuar')), findsOneWidget);
    });
  });
}
