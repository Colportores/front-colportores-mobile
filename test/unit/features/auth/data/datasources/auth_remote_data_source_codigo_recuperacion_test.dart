// El enlace de recuperación con código de un solo uso (`?token_hash=<código>&type=recovery`, la
// plantilla nueva del correo, backend-supabase#313): `supabase_flutter` no lo canjea, la app lo
// hace con `verifyOTP(type: recovery, tokenHash:)` y da los mismos resultados que el enlace viejo
// con `?code=` (válido, vencido o ya usado, sin conexión). Mock de `GoTrueClient`, sin red.
import 'dart:async';
import 'dart:io';

import 'package:colportores_mobile/core/config/config_supabase.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source_supabase.dart';
import 'package:colportores_mobile/features/auth/data/datasources/registro_enlaces_auth.dart';
import 'package:colportores_mobile/features/auth/domain/entities/enlace_recuperacion.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../helpers/logger_mudo.dart';

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _FakeUser extends Fake implements User {
  @override
  String get id => '01920000-0000-7000-8000-000000000001';
}

class _FakeSession extends Fake implements Session {
  @override
  User get user => _FakeUser();
  @override
  String get accessToken => 'jwt';
}

void main() {
  setUpAll(() => registerFallbackValue(OtpType.recovery));

  late _MockGoTrueClient auth;
  late StreamController<AuthState> cambios;
  late RegistroEnlacesAuth registro;
  late List<EnlaceRecuperacion> eventos;
  late DateTime ahora;

  Uri enlace(String codigo, {String type = 'recovery'}) =>
      Uri.parse('${ConfigSupabase.redirectRecuperacion}?token_hash=$codigo&type=$type');

  AuthResponse conSesion() => AuthResponse(session: _FakeSession());

  /// `verifyOTP` que sirve: igual que gotrue, deja el evento `passwordRecovery` en el stream.
  void sirve() {
    when(
      () => auth.verifyOTP(
        type: any(named: 'type'),
        tokenHash: any(named: 'tokenHash'),
      ),
    ).thenAnswer((_) async {
      cambios.add(AuthState(AuthChangeEvent.passwordRecovery, _FakeSession()));
      return conSesion();
    });
  }

  void falla(Object error) => when(
    () => auth.verifyOTP(
      type: any(named: 'type'),
      tokenHash: any(named: 'tokenHash'),
    ),
  ).thenAnswer((_) async => throw error);

  /// Escucha `enlacesRecuperacion` como lo hace la raíz de la app, durante toda su vida.
  StreamSubscription<EnlaceRecuperacion> escuchar() {
    final suscripcion = AuthRemoteDataSourceSupabase(
      auth,
      enlacesEntrantes: const Stream<Uri>.empty(),
      registroEnlaces: registro,
      logger: loggerMudo(),
    ).enlacesRecuperacion.listen(eventos.add);
    addTearDown(suscripcion.cancel);
    return suscripcion;
  }

  Future<void> asentar() => Future<void>.delayed(Duration.zero);

  setUp(() {
    auth = _MockGoTrueClient();
    cambios = StreamController<AuthState>.broadcast();
    ahora = DateTime.utc(2026, 11, 26, 10);
    registro = RegistroEnlacesAuth(ahora: () => ahora);
    eventos = [];
    when(() => auth.onAuthStateChange).thenAnswer((_) => cambios.stream);
  });

  tearDown(() => cambios.close());

  void llega(Uri uri) => registro.esCallbackDeAuth(uri);

  group('canje del código con verifyOTP', () {
    test('un enlace válido se canjea con type recovery y el código, y abre la pantalla de la '
        'contraseña nueva una sola vez', () async {
      sirve();
      escuchar();

      llega(enlace('codigo-1'));
      await asentar();

      verify(() => auth.verifyOTP(type: OtpType.recovery, tokenHash: 'codigo-1')).called(1);
      expect(eventos, [EnlaceRecuperacion.valido]);
    });

    test(
      'vencido o ya usado (el servidor lo rechaza) da la pantalla única de enlace vencido',
      () async {
        falla(const AuthApiException('Token has expired or is invalid', statusCode: '403'));
        escuchar();

        llega(enlace('codigo-1'));
        await asentar();

        expect(eventos, [EnlaceRecuperacion.vencido]);
      },
    );

    test('sin red no dice que venció: da sin conexión (gotrue, socket, cliente http o tope de '
        'tiempo)', () async {
      escuchar();
      for (final (i, error) in <Object>[
        AuthRetryableFetchException(message: 'sin red'),
        const SocketException('sin red'),
        http.ClientException('sin red'),
        TimeoutException('lento'),
      ].indexed) {
        falla(error);
        llega(enlace('codigo-$i'));
        await asentar();
      }

      expect(eventos, List.filled(4, EnlaceRecuperacion.sinConexion));
    });

    test('sin conexión no gasta el enlace: al tocarlo de nuevo con red se canjea', () async {
      escuchar();
      falla(AuthRetryableFetchException(message: 'sin red'));
      llega(enlace('codigo-1'));
      await asentar();

      sirve();
      // Otro toque del mismo enlace, pasado el plazo de «un mismo toque».
      ahora = ahora.add(const Duration(minutes: 1));
      llega(enlace('codigo-1'));
      await asentar();

      expect(eventos, [EnlaceRecuperacion.sinConexion, EnlaceRecuperacion.valido]);
    });

    test('un código vacío es un enlace roto: vencido, sin llamar al servidor', () async {
      escuchar();

      llega(enlace(''));
      await asentar();

      expect(eventos, [EnlaceRecuperacion.vencido]);
      verifyNever(
        () => auth.verifyOTP(
          type: any(named: 'type'),
          tokenHash: any(named: 'tokenHash'),
        ),
      );
    });

    test('una respuesta sin sesión no sirve: vencido', () async {
      when(
        () => auth.verifyOTP(
          type: any(named: 'type'),
          tokenHash: any(named: 'tokenHash'),
        ),
      ).thenAnswer((_) async => AuthResponse());
      escuchar();

      llega(enlace('codigo-1'));
      await asentar();

      expect(eventos, [EnlaceRecuperacion.vencido]);
    });

    test(
      'un fallo inesperado del canje se avisa como vencido y no traba los enlaces siguientes',
      () async {
        escuchar();
        falla(StateError('algo raro'));
        llega(enlace('codigo-1'));
        await asentar();

        sirve();
        llega(enlace('codigo-2'));
        await asentar();

        expect(eventos, [EnlaceRecuperacion.vencido, EnlaceRecuperacion.valido]);
      },
    );

    test('el enlace que llegó antes de que la app escuchara (arranque en frío) se canjea al '
        'empezar a escuchar', () async {
      sirve();
      llega(enlace('codigo-1'));
      verifyNever(
        () => auth.verifyOTP(
          type: any(named: 'type'),
          tokenHash: any(named: 'tokenHash'),
        ),
      );

      escuchar();
      await asentar();

      verify(() => auth.verifyOTP(type: OtpType.recovery, tokenHash: 'codigo-1')).called(1);
      expect(eventos, [EnlaceRecuperacion.valido]);
    });

    test('doble toque: el mismo enlace entregado dos veces se canjea una sola vez', () async {
      sirve();
      escuchar();

      llega(enlace('codigo-1'));
      llega(enlace('codigo-1'));
      await asentar();

      verify(() => auth.verifyOTP(type: OtpType.recovery, tokenHash: 'codigo-1')).called(1);
      expect(eventos, [EnlaceRecuperacion.valido]);
    });

    test(
      'dos enlaces seguidos se canjean en fila y sus resultados llegan en orden, sin pisarse',
      () async {
        final primero = Completer<AuthResponse>();
        var llamadas = 0;
        when(
          () => auth.verifyOTP(
            type: any(named: 'type'),
            tokenHash: any(named: 'tokenHash'),
          ),
        ).thenAnswer((_) {
          llamadas++;
          if (llamadas == 1) return primero.future;
          cambios.add(AuthState(AuthChangeEvent.passwordRecovery, _FakeSession()));
          return Future.value(conSesion());
        });
        escuchar();

        llega(enlace('viejo'));
        llega(enlace('nuevo'));
        await asentar();
        expect(llamadas, 1, reason: 'el segundo espera al primero');

        primero.completeError(const AuthApiException('vencido', statusCode: '403'));
        await asentar();

        expect(llamadas, 2);
        expect(eventos, [EnlaceRecuperacion.vencido, EnlaceRecuperacion.valido]);
      },
    );

    test('un servidor que no contesta no traba el turno: a los 30 s es sin conexión y el enlace '
        'siguiente se canjea', () {
      fakeAsync((reloj) {
        final colgado = Completer<AuthResponse>();
        when(
          () => auth.verifyOTP(
            type: any(named: 'type'),
            tokenHash: any(named: 'tokenHash'),
          ),
        ).thenAnswer((_) => colgado.future);
        escuchar();

        llega(enlace('codigo-1'));
        reloj.elapse(const Duration(seconds: 29));
        expect(eventos, isEmpty);
        reloj.elapse(const Duration(seconds: 2));
        expect(eventos, [EnlaceRecuperacion.sinConexion]);

        sirve();
        llega(enlace('codigo-2'));
        reloj.flushMicrotasks();
        expect(eventos, [EnlaceRecuperacion.sinConexion, EnlaceRecuperacion.valido]);
      });
    });

    test('volver atrás y reentrar: al dejar de escuchar no se canjea nada, y al escuchar de nuevo '
        'se canjea lo que llegó mientras tanto', () async {
      sirve();
      final suscripcion = escuchar();
      await suscripcion.cancel();

      llega(enlace('codigo-1'));
      await asentar();
      verifyNever(
        () => auth.verifyOTP(
          type: any(named: 'type'),
          tokenHash: any(named: 'tokenHash'),
        ),
      );

      escuchar();
      await asentar();

      expect(eventos, [EnlaceRecuperacion.valido]);
    });

    test(
      'el enlace viejo con ?code= sigue por supabase_flutter: no se llama a verifyOTP',
      () async {
        escuchar();

        final deAuth = registro.esCallbackDeAuth(
          Uri.parse('${ConfigSupabase.redirectRecuperacion}?code=abc'),
        );
        cambios.add(AuthState(AuthChangeEvent.passwordRecovery, _FakeSession()));
        await asentar();

        expect(deAuth, isTrue);
        expect(eventos, [EnlaceRecuperacion.valido]);
        verifyNever(
          () => auth.verifyOTP(
            type: any(named: 'type'),
            tokenHash: any(named: 'tokenHash'),
          ),
        );
      },
    );

    test('un type que no es recovery no se canjea', () async {
      escuchar();

      llega(enlace('codigo-1', type: 'signup'));
      await asentar();

      expect(eventos, isEmpty);
      verifyNever(
        () => auth.verifyOTP(
          type: any(named: 'type'),
          tokenHash: any(named: 'tokenHash'),
        ),
      );
    });
  });
}
