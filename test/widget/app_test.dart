// Cubre el listener de deep link de verificación de email en la raíz de la app (lib/app.dart):
// `erroresVerificacionEmailProvider` navega a VerificacionEmailPage(expirado) solo cuando no hay
// sesión activa — con sesión, el evento es de un enlace viejo y no debe interrumpir al usuario.
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

void main() {
  group('ColportoresApp — deep link de verificación con error', () {
    testWidgets('sin sesión activa: navega a la pantalla en estado expirado', (tester) async {
      final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
      await tester.pumpWidget(_app(remote: remote));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_enviar')), findsOneWidget);

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('verificacion_email_titulo')), findsOneWidget);
      expect(find.text('El enlace no es válido'), findsOneWidget);
    });

    testWidgets('con sesión activa: no navega ni toca la pila (enlace viejo, ya verificado)', (
      tester,
    ) async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'ana@example.com': 'secreto123'},
      );
      await tester.pumpWidget(_app(remote: remote));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
      await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
      await tester.tap(find.byKey(const Key('login_enviar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inicio_email')), findsOneWidget);

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inicio_email')), findsOneWidget);
      expect(find.byKey(const Key('verificacion_email_titulo')), findsNothing);
    });
  });
}
