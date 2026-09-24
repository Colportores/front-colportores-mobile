// Test de la capa data contra Supabase Auth mockeado (mocktail sobre GoTrueClient).
// Importa supabase_flutter (que arrastra Flutter), así que usa flutter_test y no `test`.
import 'dart:async';

import 'package:colportores_mobile/core/config/config_supabase.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source_supabase.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../helpers/logger_mudo.dart';

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockGoTrueAdminApi extends Mock implements GoTrueAdminApi {}

/// Fakes (sin `when`) para lo que devuelve GoTrue: mocktail prohíbe stubear dentro de otro
/// stub, y estos objetos se construyen justamente dentro de `thenAnswer`.
class _FakeUser extends Fake implements User {
  _FakeUser({required this.id, this.email, this.identities, this.appMetadata = const {}});

  @override
  final String id;
  @override
  final String? email;
  @override
  final List<UserIdentity>? identities;
  @override
  final Map<String, dynamic> appMetadata;
}

class _FakeSession extends Fake implements Session {
  _FakeSession({
    required this.user,
    this.accessToken = 'jwt',
    this.expiresAt,
    this.isExpired = false,
  });

  @override
  final User user;
  @override
  final String accessToken;
  @override
  int? expiresAt;
  @override
  int? get expiresIn => 3600;
  @override
  final bool isExpired;
}

void main() {
  setUpAll(() => registerFallbackValue(SignOutScope.local));

  late _MockGoTrueClient auth;
  late StreamController<AuthState> cambios;

  const usuarioId = '01920000-0000-7000-8000-000000000001';
  final expiraEn = DateTime.utc(2026, 9, 4, 20);
  final expiraEnSegundos = expiraEn.millisecondsSinceEpoch ~/ 1000;

  _FakeSession sesionSupabase({
    bool vencida = false,
    String? email = 'ana@example.com',
    String accessToken = 'jwt',
    // Las sesiones de este helper representan, salvo que se diga lo contrario, un login con
    // Google (es el único flujo que las consume vía onAuthStateChange en estos tests).
    String proveedor = 'google',
  }) => _FakeSession(
    user: _FakeUser(id: usuarioId, email: email, appMetadata: {'provider': proveedor}),
    accessToken: accessToken,
    expiresAt: expiraEnSegundos,
    isExpired: vencida,
  );

  AuthResponse respuestaCon({Session? sesion, User? user}) =>
      AuthResponse(session: sesion, user: user);

  AuthRemoteDataSourceSupabase dataSource({
    LanzadorOAuth? lanzarOAuth,
    Duration esperaOAuth = const Duration(seconds: 1),
  }) => AuthRemoteDataSourceSupabase(
    auth,
    lanzarOAuth: lanzarOAuth,
    esperaOAuth: esperaOAuth,
    logger: loggerMudo(),
  );

  setUpAll(() {
    // Hace falta un fallback para poder usar `any(named: 'type')` con `resend` (mocktail exige
    // uno para cualquier tipo no primitivo, aunque el valor real no importe).
    registerFallbackValue(OtpType.signup);
  });

  setUp(() {
    auth = _MockGoTrueClient();
    cambios = StreamController<AuthState>.broadcast();
    when(() => auth.onAuthStateChange).thenAnswer((_) => cambios.stream);
  });

  tearDown(() => cambios.close());

  group('AuthRemoteDataSourceSupabase.iniciarSesion', () {
    test(
      'dado credenciales válidas, cuando entra, mapea la sesión de Supabase a SesionModel',
      () async {
        when(
          () => auth.signInWithPassword(email: 'ana@example.com', password: 'secreto123'),
        ).thenAnswer((_) async => respuestaCon(sesion: sesionSupabase()));

        final sesion = await dataSource().iniciarSesion(
          email: 'ana@example.com',
          password: 'secreto123',
        );

        expect(sesion.usuarioId, usuarioId);
        expect(sesion.email, 'ana@example.com');
        expect(sesion.accessToken, 'jwt');
        expect(sesion.expiraEn, expiraEn);
      },
    );

    test('dado credenciales inválidas (error_code), lanza CredencialesInvalidasException', () {
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(
        const AuthApiException(
          'Invalid login credentials',
          statusCode: '400',
          code: 'invalid_credentials',
        ),
      );

      expect(
        () => dataSource().iniciarSesion(email: 'ana@example.com', password: 'mala'),
        throwsA(isA<CredencialesInvalidasException>()),
      );
    });

    test('dado un GoTrue viejo sin error_code, traduce por status + texto', () {
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(const AuthApiException('Invalid login credentials', statusCode: '400'));

      expect(
        () => dataSource().iniciarSesion(email: 'ana@example.com', password: 'mala'),
        throwsA(isA<CredencialesInvalidasException>()),
      );
    });

    test('dado un email sin confirmar, lanza ServidorException con mensaje para el usuario', () {
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(
        const AuthApiException(
          'Email not confirmed',
          statusCode: '400',
          code: 'email_not_confirmed',
        ),
      );

      expect(
        () => dataSource().iniciarSesion(email: 'ana@example.com', password: 'secreto123'),
        throwsA(
          isA<ServidorException>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('verificar tu correo'),
          ),
        ),
      );
    });

    test('dado que la contraseña es débil, lanza PasswordDebilException', () {
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(const AuthApiException('Password is too weak', code: 'weak_password'));

      expect(
        () => dataSource().iniciarSesion(email: 'ana@example.com', password: 'secreto123'),
        throwsA(isA<PasswordDebilException>()),
      );
    });

    test(
      'dado el límite de emails/intentos de Supabase (429), lanza ServidorException con mensaje',
      () {
        when(
          () => auth.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenThrow(
          const AuthApiException(
            'Email rate limit exceeded',
            statusCode: '429',
            code: 'over_email_send_rate_limit',
          ),
        );

        expect(
          () => dataSource().iniciarSesion(email: 'ana@example.com', password: 'secreto123'),
          throwsA(
            isA<ServidorException>().having(
              (e) => e.mensaje,
              'mensaje',
              contains('Demasiados intentos'),
            ),
          ),
        );
      },
    );

    test('dado un 429 sin error_code, también avisa el límite de intentos', () {
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(const AuthApiException('Too Many Requests', statusCode: '429'));

      expect(
        () => dataSource().iniciarSesion(email: 'ana@example.com', password: 'secreto123'),
        throwsA(
          isA<ServidorException>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('Demasiados intentos'),
          ),
        ),
      );
    });

    test('dado que no hay red, lanza SinConexionException', () {
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(AuthRetryableFetchException(message: 'SocketException'));

      expect(
        () => dataSource().iniciarSesion(email: 'ana@example.com', password: 'secreto123'),
        throwsA(isA<SinConexionException>()),
      );
    });

    test('dado un error de Supabase sin traducción, lanza ServidorException con el status y un '
        'mensaje genérico con el código — nunca el texto crudo de Supabase (puede llevar PII), '
        'para signup_disabled, validation_failed, bad_json, etc.', () {
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(
        const AuthApiException(
          'boom con datos del usuario',
          statusCode: '500',
          code: 'unexpected_failure',
        ),
      );

      expect(
        () => dataSource().iniciarSesion(email: 'ana@example.com', password: 'secreto123'),
        throwsA(
          isA<ServidorException>()
              .having((e) => e.status, 'status', 500)
              .having(
                (e) => e.mensaje,
                'mensaje',
                'No se pudo completar la operación (unexpected_failure).',
              )
              .having((e) => e.mensaje, 'mensaje', isNot(contains('boom con datos del usuario'))),
        ),
      );
    });

    test('dado una respuesta 200 sin sesión (contrato roto), lanza ServidorException', () {
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => respuestaCon());

      expect(
        () => dataSource().iniciarSesion(email: 'ana@example.com', password: 'secreto123'),
        throwsA(isA<ServidorException>()),
      );
    });
  });

  group('AuthRemoteDataSourceSupabase.solicitarRecuperacionPassword', () {
    test('cuando solicita, llama a resetPasswordForEmail con el emailRedirectTo', () async {
      when(
        () =>
            auth.resetPasswordForEmail('ana@example.com', redirectTo: ConfigSupabase.redirectOAuth),
      ).thenAnswer((_) async {});

      await dataSource().solicitarRecuperacionPassword('ana@example.com');

      verify(
        () =>
            auth.resetPasswordForEmail('ana@example.com', redirectTo: ConfigSupabase.redirectOAuth),
      ).called(1);
    });

    test('dado el límite de emails de Supabase, lanza ServidorException con mensaje', () {
      when(() => auth.resetPasswordForEmail(any(), redirectTo: any(named: 'redirectTo'))).thenThrow(
        const AuthApiException(
          'Email rate limit exceeded',
          statusCode: '429',
          code: 'over_email_send_rate_limit',
        ),
      );

      expect(
        () => dataSource().solicitarRecuperacionPassword('ana@example.com'),
        throwsA(
          isA<ServidorException>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('Demasiados intentos'),
          ),
        ),
      );
    });

    test('dado que no hay red, lanza SinConexionException', () {
      when(
        () => auth.resetPasswordForEmail(any(), redirectTo: any(named: 'redirectTo')),
      ).thenThrow(AuthRetryableFetchException(message: 'SocketException'));

      expect(
        () => dataSource().solicitarRecuperacionPassword('ana@example.com'),
        throwsA(isA<SinConexionException>()),
      );
    });
  });

  group('AuthRemoteDataSourceSupabase.registrar', () {
    Future<SesionModel?> registrar(AuthRemoteDataSourceSupabase ds) => ds.registrar(
      nombre: 'Ana',
      apellido: 'Pérez',
      cedula: '12345678',
      email: 'ana@example.com',
      password: 'secreto123',
    );

    test('dado un email nuevo, cuando registra, manda el perfil y el emailRedirectTo, y devuelve '
        'la sesión', () async {
      when(
        () => auth.signUp(
          email: 'ana@example.com',
          password: 'secreto123',
          data: {'nombre': 'Ana', 'apellido': 'Pérez', 'cedula': '12345678'},
          emailRedirectTo: ConfigSupabase.redirectOAuth,
        ),
      ).thenAnswer((_) async => respuestaCon(sesion: sesionSupabase()));

      final sesion = await dataSource().registrar(
        nombre: 'Ana',
        apellido: 'Pérez',
        cedula: '12345678',
        email: 'ana@example.com',
        password: 'secreto123',
      );

      expect(sesion?.usuarioId, usuarioId);
    });

    test('dado un email ya registrado (error_code), lanza EmailYaRegistradoException', () {
      when(
        () => auth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
          data: any(named: 'data'),
          emailRedirectTo: any(named: 'emailRedirectTo'),
        ),
      ).thenThrow(
        const AuthApiException(
          'User already registered',
          statusCode: '422',
          code: 'user_already_exists',
        ),
      );

      expect(() => registrar(dataSource()), throwsA(isA<EmailYaRegistradoException>()));
    });

    test(
      'dado un email ya registrado con confirmación activa (usuario sin identidades), lanza EmailYaRegistradoException',
      () {
        final user = _FakeUser(id: usuarioId, identities: const []);
        when(
          () => auth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            data: any(named: 'data'),
            emailRedirectTo: any(named: 'emailRedirectTo'),
          ),
        ).thenAnswer((_) async => respuestaCon(user: user));

        expect(() => registrar(dataSource()), throwsA(isA<EmailYaRegistradoException>()));
      },
    );

    test(
      'dado que hace falta confirmar el email (sin sesión), devuelve null — no es un error',
      () async {
        final user = _FakeUser(id: usuarioId);
        when(
          () => auth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            data: any(named: 'data'),
            emailRedirectTo: any(named: 'emailRedirectTo'),
          ),
        ).thenAnswer((_) async => respuestaCon(user: user));

        expect(await registrar(dataSource()), isNull);
      },
    );
  });

  group('AuthRemoteDataSourceSupabase.obtenerSesionActual', () {
    test('dado que no hay sesión persistida, devuelve null sin tocar la red', () async {
      when(() => auth.currentSession).thenReturn(null);

      expect(await dataSource().obtenerSesionActual(), isNull);
      verifyNever(() => auth.refreshSession());
    });

    test('dado una sesión vigente, la devuelve mapeada', () async {
      when(() => auth.currentSession).thenReturn(sesionSupabase());

      final sesion = await dataSource().obtenerSesionActual();

      expect(sesion?.usuarioId, usuarioId);
      verifyNever(() => auth.refreshSession());
    });

    test('dado una sesión vencida, la refresca y devuelve la nueva', () async {
      when(() => auth.currentSession).thenReturn(sesionSupabase(vencida: true));
      final nueva = sesionSupabase(accessToken: 'jwt-nuevo');
      when(() => auth.refreshSession()).thenAnswer((_) async => respuestaCon(sesion: nueva));

      final sesion = await dataSource().obtenerSesionActual();

      expect(sesion?.accessToken, 'jwt-nuevo');
    });

    test('dado una sesión vencida y sin red, lanza SinConexionException', () {
      when(() => auth.currentSession).thenReturn(sesionSupabase(vencida: true));
      when(() => auth.refreshSession()).thenThrow(AuthRetryableFetchException(message: 'x'));

      expect(() => dataSource().obtenerSesionActual(), throwsA(isA<SinConexionException>()));
    });

    test('dado una sesión sin expiresAt, estima la expiración con expiresIn', () async {
      final sesion = sesionSupabase(email: null)..expiresAt = null;
      when(() => auth.currentSession).thenReturn(sesion);
      final antes = DateTime.now().toUtc();

      final modelo = await dataSource().obtenerSesionActual();

      expect(modelo?.email, '');
      expect(modelo?.expiraEn.isAfter(antes.add(const Duration(minutes: 59))), isTrue);
    });
  });

  group('AuthRemoteDataSourceSupabase.sesionEnElCliente', () {
    test('devuelve la sesión que el cliente tiene ahora, sin refrescar ni tocar la red', () {
      when(() => auth.currentSession).thenReturn(sesionSupabase(accessToken: 'jwt-renovado'));

      final sesion = dataSource().sesionEnElCliente();

      expect(sesion?.accessToken, 'jwt-renovado');
      expect(sesion?.usuarioId, usuarioId);
      verifyNever(() => auth.refreshSession());
    });

    test('sin sesión en el cliente, devuelve null', () {
      when(() => auth.currentSession).thenReturn(null);

      expect(dataSource().sesionEnElCliente(), isNull);
    });
  });

  group('AuthRemoteDataSourceSupabase.cerrarSesion', () {
    test('cuando cierra sesión, llama a signOut', () async {
      when(() => auth.signOut()).thenAnswer((_) async {});

      await dataSource().cerrarSesion('jwt');

      verify(() => auth.signOut()).called(1);
    });

    test(
      'dado que el cliente refrescó el token, cuando cierra sesión con el token del login, igual '
      'llama a signOut (y no revoca por token)',
      () async {
        final admin = _MockGoTrueAdminApi();
        when(() => auth.admin).thenReturn(admin);
        when(() => auth.currentSession).thenReturn(sesionSupabase());
        when(() => auth.signOut()).thenAnswer((_) async {});

        await dataSource().cerrarSesion('jwt-del-login-ya-refrescado');

        verify(() => auth.signOut()).called(1);
        verifyNever(() => admin.signOut(any(), scope: any(named: 'scope')));
      },
    );

    test('dado que no hay red, lanza SinConexionException', () {
      when(() => auth.signOut()).thenThrow(AuthRetryableFetchException(message: 'x'));

      expect(() => dataSource().cerrarSesion('jwt'), throwsA(isA<SinConexionException>()));
    });
  });

  group('AuthRemoteDataSourceSupabase.revocarSesion', () {
    test('revoca solo esa sesión (scope local) y no toca el cliente', () async {
      final admin = _MockGoTrueAdminApi();
      when(() => auth.admin).thenReturn(admin);
      when(() => admin.signOut('jwt-viejo', scope: SignOutScope.local)).thenAnswer((_) async {});

      await dataSource().revocarSesion('jwt-viejo');

      verify(() => admin.signOut('jwt-viejo', scope: SignOutScope.local)).called(1);
      verifyNever(() => admin.signOut(any(), scope: SignOutScope.global));
      verifyNever(() => auth.signOut());
    });

    test('dado que no hay red, lanza SinConexionException', () {
      final admin = _MockGoTrueAdminApi();
      when(() => auth.admin).thenReturn(admin);
      when(
        () => admin.signOut(any(), scope: any(named: 'scope')),
      ).thenThrow(AuthRetryableFetchException(message: 'x'));

      expect(() => dataSource().revocarSesion('jwt'), throwsA(isA<SinConexionException>()));
    });
  });

  group('AuthRemoteDataSourceSupabase.iniciarSesionConGoogle', () {
    test(
      'dado que el navegador abre y vuelve el deep link, cuando llega signedIn, devuelve la sesión',
      () async {
        OAuthProvider? proveedor;
        String? redirect;
        final ds = dataSource(
          lanzarOAuth: (p, r) async {
            proveedor = p;
            redirect = r;
            // Simula la vuelta del deep link después de abrir el navegador.
            scheduleMicrotask(
              () => cambios.add(AuthState(AuthChangeEvent.signedIn, sesionSupabase())),
            );
            return true;
          },
        );

        final sesion = await ds.iniciarSesionConGoogle();

        expect(sesion.usuarioId, usuarioId);
        expect(proveedor, OAuthProvider.google);
        expect(redirect, ConfigSupabase.redirectOAuth);
        expect(cambios.hasListener, isFalse, reason: 'cancela la suscripción al terminar');
      },
    );

    test('ignora eventos que no son signedIn con sesión', () async {
      final ds = dataSource(
        lanzarOAuth: (_, _) async {
          scheduleMicrotask(() {
            cambios.add(const AuthState(AuthChangeEvent.initialSession, null));
            cambios.add(AuthState(AuthChangeEvent.signedIn, sesionSupabase()));
          });
          return true;
        },
      );

      final sesion = await ds.iniciarSesionConGoogle();

      expect(sesion.accessToken, 'jwt');
    });

    test(
      'dado que el usuario no vuelve del navegador, cuando vence la espera, lanza ServidorException',
      () async {
        final ds = dataSource(
          lanzarOAuth: (_, _) async => true,
          esperaOAuth: const Duration(milliseconds: 20),
        );

        await expectLater(
          ds.iniciarSesionConGoogle(),
          throwsA(isA<ServidorException>().having((e) => e.mensaje, 'mensaje', contains('Google'))),
        );
        expect(cambios.hasListener, isFalse);
      },
    );

    test('ignora un signedIn de otro proveedor (p. ej. confirmar email, mismo redirect) y sigue '
        'esperando al de Google', () async {
      final ds = dataSource(
        lanzarOAuth: (_, _) async {
          // Mismo redirect que Google: llega primero el signedIn de confirmar el email, y
          // recién después el de Google — no hay que resolver con el primero.
          scheduleMicrotask(
            () => cambios.add(
              AuthState(AuthChangeEvent.signedIn, sesionSupabase(proveedor: 'email')),
            ),
          );
          Future<void>.delayed(const Duration(milliseconds: 10), () {
            cambios.add(AuthState(AuthChangeEvent.signedIn, sesionSupabase()));
          });
          return true;
        },
      );

      final sesion = await ds.iniciarSesionConGoogle();

      expect(sesion.usuarioId, usuarioId);
    });

    test('dado que no se pudo abrir el navegador (false), lanza ServidorException', () {
      final ds = dataSource(lanzarOAuth: (_, _) async => false);

      expect(ds.iniciarSesionConGoogle(), throwsA(isA<ServidorException>()));
    });

    test('dado que signInWithOAuth lanza AuthException, la traduce', () {
      final ds = dataSource(
        lanzarOAuth: (_, _) => throw AuthRetryableFetchException(message: 'sin red'),
      );

      expect(ds.iniciarSesionConGoogle(), throwsA(isA<SinConexionException>()));
    });
  });

  group('AuthRemoteDataSourceSupabase.reenviarVerificacion', () {
    test('cuando reenvía, llama a resend con type signup y el emailRedirectTo', () async {
      when(
        () => auth.resend(
          email: 'ana@example.com',
          type: OtpType.signup,
          emailRedirectTo: ConfigSupabase.redirectOAuth,
        ),
      ).thenAnswer((_) async => ResendResponse());

      await dataSource().reenviarVerificacion('ana@example.com');

      verify(
        () => auth.resend(
          email: 'ana@example.com',
          type: OtpType.signup,
          emailRedirectTo: ConfigSupabase.redirectOAuth,
        ),
      ).called(1);
    });

    test('dado el límite de emails de Supabase, lanza ServidorException con mensaje', () {
      when(
        () => auth.resend(
          email: any(named: 'email'),
          type: any(named: 'type'),
          emailRedirectTo: any(named: 'emailRedirectTo'),
        ),
      ).thenThrow(
        const AuthApiException(
          'Email rate limit exceeded',
          statusCode: '429',
          code: 'over_email_send_rate_limit',
        ),
      );

      expect(
        () => dataSource().reenviarVerificacion('ana@example.com'),
        throwsA(
          isA<ServidorException>().having(
            (e) => e.mensaje,
            'mensaje',
            contains('Demasiados intentos'),
          ),
        ),
      );
    });
  });

  group('AuthRemoteDataSourceSupabase.erroresVerificacionEmail', () {
    test('dado un error otp_expired en el stream, emite el evento', () async {
      final futuro = dataSource().erroresVerificacionEmail.first;

      cambios.addError(
        const AuthApiException(
          'Email link is invalid or has expired',
          statusCode: 'otp_expired',
          code: 'access_denied',
        ),
      );

      await expectLater(futuro, completes);
    });

    test('ignora otros errores del stream (p. ej. un OAuth cancelado)', () async {
      final eventos = <void>[];
      final suscripcion = dataSource().erroresVerificacionEmail.listen(eventos.add);
      addTearDown(suscripcion.cancel);

      cambios.addError(const AuthApiException('access_denied', code: 'access_denied'));
      await Future<void>.delayed(Duration.zero);

      expect(eventos, isEmpty);
    });

    test('ignora eventos normales del stream (signedIn, etc.)', () async {
      final eventos = <void>[];
      final suscripcion = dataSource().erroresVerificacionEmail.listen(eventos.add);
      addTearDown(suscripcion.cancel);

      cambios.add(AuthState(AuthChangeEvent.signedIn, sesionSupabase()));
      await Future<void>.delayed(Duration.zero);

      expect(eventos, isEmpty);
    });
  });
}
