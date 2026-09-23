// Cubre el listener de deep link de verificación de email en la raíz de la app (lib/app.dart):
// `erroresVerificacionEmailProvider` navega a VerificacionEmailPage(expirado) solo cuando no hay
// sesión activa — con sesión, el evento es de un enlace viejo y no debe interrumpir al usuario.
import 'dart:async';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({required AuthRemoteDataSourceEnMemoria remote, AuthLocalDataSource? local}) =>
    ProviderScope(
      overrides: [
        authRemoteDataSourceProvider.overrideWithValue(remote),
        authLocalDataSourceProvider.overrideWithValue(local ?? AuthLocalDataSourceEnMemoria()),
      ],
      child: const ColportoresApp(),
    );

/// Local que no resuelve `leerSesion()` hasta que se llama a [resolver] — simula el arranque en
/// frío, donde `sesionActual()` (I/O real) todavía no terminó cuando el deep link de error llega.
class _LocalConDemora implements AuthLocalDataSource {
  _LocalConDemora(this._sesion);

  final SesionModel? _sesion;
  final _completer = Completer<void>();

  @override
  Future<SesionModel?> leerSesion() async {
    await _completer.future;
    return _sesion;
  }

  @override
  Future<void> guardarSesion(SesionModel sesion) async {}

  @override
  Future<void> borrarSesion() async {}

  void resolver() => _completer.complete();
}

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

      // Empuja una ruta arriba de "/" (InicioPage) para que "la pila queda intacta" pruebe algo:
      // sin esto, "/" es la única ruta y un `popUntil((r) => r.isFirst)` de más sería invisible.
      final elemento = tester.element(find.byKey(const Key('inicio_email')));
      unawaited(
        Navigator.of(elemento).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('otra pantalla', key: Key('otra_pantalla'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('otra_pantalla')), findsOneWidget);

      remote.simularEnlaceVerificacionInvalido();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('otra_pantalla')), findsOneWidget);
      expect(find.byKey(const Key('verificacion_email_titulo')), findsNothing);
    });

    testWidgets(
      'sesión persistida pero todavía resolviendo (arranque en frío): espera y no navega',
      (tester) async {
        final remote = AuthRemoteDataSourceEnMemoria(credenciales: const {});
        final local = _LocalConDemora(
          SesionModel(
            usuarioId: '01920000-0000-7000-8000-000000000001',
            email: 'ana@example.com',
            accessToken: 'jwt',
            expiraEn: DateTime.now().toUtc().add(const Duration(hours: 1)),
          ),
        );

        await tester.pumpWidget(_app(remote: remote, local: local));
        await tester.pump();

        // sesionProvider sigue en AsyncLoading (leerSesion no resolvió): se ve el spinner de
        // `home:`, no el login ni la pantalla de verificación.
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        // El deep link de error llega ANTES de que la sesión persistida termine de leerse — el
        // caso típico del arranque en frío desde el enlace viejo del mail.
        remote.simularEnlaceVerificacionInvalido();
        await tester.pump();

        expect(
          find.byKey(const Key('verificacion_email_titulo')),
          findsNothing,
          reason: 'todavía no se supo si hay sesión: no debería haber navegado',
        );

        local.resolver();
        await tester.pumpAndSettle();

        // Había sesión: el evento era de un enlace viejo. Entra directo a Inicio, nunca pasó por
        // la pantalla de verificación.
        expect(find.byKey(const Key('inicio_email')), findsOneWidget);
        expect(find.byKey(const Key('verificacion_email_titulo')), findsNothing);
      },
    );
  });

  group('ColportoresApp — bloqueo de acceso hasta verificar (HU-AUTH-002)', () {
    testWidgets(
      'cuenta sin verificar: el login rechaza con el mensaje inline y no entra a Inicio',
      (tester) async {
        final remote = AuthRemoteDataSourceEnMemoria(
          credenciales: const {},
          requiereVerificacionAlRegistrar: true,
        );
        await remote.registrar(
          nombre: 'Lucía',
          apellido: 'Silva',
          cedula: '12345678',
          email: 'lucia.silva@correo.com',
          password: 'Secreto123',
        );

        await tester.pumpWidget(_app(remote: remote));
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('login_email')), 'lucia.silva@correo.com');
        await tester.enterText(find.byKey(const Key('login_password')), 'Secreto123');
        await tester.tap(find.byKey(const Key('login_enviar')));
        await tester.pumpAndSettle();

        // Bloqueado: ni entra a Inicio ni queda "logueado a medias" en ninguna otra pantalla.
        expect(find.byKey(const Key('inicio_email')), findsNothing);
        expect(find.byKey(const Key('login_error_general')), findsOneWidget);
        expect(
          find.textContaining('verificar tu correo'),
          findsOneWidget,
          reason: 'mensaje inline de "email sin confirmar", igual que devuelve Supabase',
        );
        // Sigue en el login: el intento no dejó una sesión a medio abrir.
        expect(find.byKey(const Key('login_enviar')), findsOneWidget);
      },
    );

    testWidgets(
      'una vez verificada la cuenta, el mismo login que antes fue rechazado ahora entra',
      (tester) async {
        final remote = AuthRemoteDataSourceEnMemoria(
          credenciales: const {},
          requiereVerificacionAlRegistrar: true,
        );
        await remote.registrar(
          nombre: 'Lucía',
          apellido: 'Silva',
          cedula: '12345678',
          email: 'lucia.silva@correo.com',
          password: 'Secreto123',
        );

        await tester.pumpWidget(_app(remote: remote));
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('login_email')), 'lucia.silva@correo.com');
        await tester.enterText(find.byKey(const Key('login_password')), 'Secreto123');
        await tester.tap(find.byKey(const Key('login_enviar')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('inicio_email')), findsNothing);

        remote.confirmarEmail('lucia.silva@correo.com');
        await tester.tap(find.byKey(const Key('login_enviar')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('inicio_email')), findsOneWidget);
      },
    );
  });
}
