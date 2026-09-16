// Test de la capa data contra Supabase Auth mockeado (mocktail sobre GoTrueClient).
// Importa supabase_flutter (que arrastra Flutter), así que usa flutter_test y no `test`.
import 'dart:async';

import 'package:colportores_mobile/core/config/config_supabase.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source_supabase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../helpers/logger_mudo.dart';

class _MockGoTrueClient extends Mock implements GoTrueClient {}

/// Fakes (sin `when`) para lo que devuelve GoTrue: mocktail prohíbe stubear dentro de otro
/// stub, y estos objetos se construyen justamente dentro de `thenAnswer`.
class _FakeUser extends Fake implements User {
  _FakeUser({required this.id, this.email, this.identities});

  @override
  final String id;
  @override
  final String? email;
  @override
  final List<UserIdentity>? identities;
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
  late _MockGoTrueClient auth;
  late StreamController<AuthState> cambios;

  const usuarioId = '01920000-0000-7000-8000-000000000001';
  final expiraEn = DateTime.utc(2026, 9, 4, 20);
  final expiraEnSegundos = expiraEn.millisecondsSinceEpoch ~/ 1000;

  _FakeSession sesionSupabase({
    bool vencida = false,
    String? email = 'ana@example.com',
    String accessToken = 'jwt',
  }) => _FakeSession(
    user: _FakeUser(id: usuarioId, email: email),
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
            contains('confirmar tu email'),
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

    test('dado un error de Supabase sin traducción, lanza ServidorException con el status', () {
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(const AuthApiException('boom', statusCode: '500', code: 'unexpected_failure'));

      expect(
        () => dataSource().iniciarSesion(email: 'ana@example.com', password: 'secreto123'),
        throwsA(isA<ServidorException>().having((e) => e.status, 'status', 500)),
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

  group('AuthRemoteDataSourceSupabase.registrar', () {
    Future<void> registrar(AuthRemoteDataSourceSupabase ds) => ds.registrar(
      nombre: 'Ana',
      apellido: 'Pérez',
      cedula: '12345678',
      email: 'ana@example.com',
      password: 'secreto123',
    );

    test(
      'dado un email nuevo, cuando registra, manda el perfil en user_metadata y devuelve la sesión',
      () async {
        when(
          () => auth.signUp(
            email: 'ana@example.com',
            password: 'secreto123',
            data: {'nombre': 'Ana', 'apellido': 'Pérez', 'cedula': '12345678'},
          ),
        ).thenAnswer((_) async => respuestaCon(sesion: sesionSupabase()));

        final sesion = await dataSource().registrar(
          nombre: 'Ana',
          apellido: 'Pérez',
          cedula: '12345678',
          email: 'ana@example.com',
          password: 'secreto123',
        );

        expect(sesion.usuarioId, usuarioId);
      },
    );

    test('dado un email ya registrado (error_code), lanza EmailYaRegistradoException', () {
      when(
        () => auth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
          data: any(named: 'data'),
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
          ),
        ).thenAnswer((_) async => respuestaCon(user: user));

        expect(() => registrar(dataSource()), throwsA(isA<EmailYaRegistradoException>()));
      },
    );

    test(
      'dado que hace falta confirmar el email (sin sesión), lanza ServidorException con mensaje',
      () {
        final user = _FakeUser(id: usuarioId);
        when(
          () => auth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            data: any(named: 'data'),
          ),
        ).thenAnswer((_) async => respuestaCon(user: user));

        expect(
          () => registrar(dataSource()),
          throwsA(
            isA<ServidorException>().having((e) => e.mensaje, 'mensaje', contains('confirmar')),
          ),
        );
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

  group('AuthRemoteDataSourceSupabase.cerrarSesion', () {
    test('cuando cierra sesión, llama a signOut', () async {
      when(() => auth.signOut()).thenAnswer((_) async {});

      await dataSource().cerrarSesion('jwt');

      verify(() => auth.signOut()).called(1);
    });

    test('dado que no hay red, lanza SinConexionException', () {
      when(() => auth.signOut()).thenThrow(AuthRetryableFetchException(message: 'x'));

      expect(() => dataSource().cerrarSesion('jwt'), throwsA(isA<SinConexionException>()));
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
}
