// De qué flujo es cada deep link de auth (HU-AUTH-005). Dart puro.
import 'package:colportores_mobile/core/config/config_supabase.dart';
import 'package:colportores_mobile/features/auth/data/datasources/registro_enlaces_auth.dart';
import 'package:test/test.dart';

void main() {
  late RegistroEnlacesAuth registro;

  setUp(() => registro = RegistroEnlacesAuth());

  Uri recuperacion(String parametros) =>
      Uri.parse('${ConfigSupabase.redirectRecuperacion}$parametros');
  Uri verificacion(String parametros) => Uri.parse('${ConfigSupabase.redirectBase}$parametros');

  group('RegistroEnlacesAuth.esCallbackDeAuth', () {
    test('con la heurística de supabase_flutter: code, access_token o error, en la query o en el '
        'fragmento, es de auth; otro link no', () {
      expect(registro.esCallbackDeAuth(verificacion('?code=abc')), isTrue);
      expect(registro.esCallbackDeAuth(verificacion('#access_token=x')), isTrue);
      expect(registro.esCallbackDeAuth(verificacion('#error=access_denied')), isTrue);
      expect(registro.esCallbackDeAuth(verificacion('?error_code=otp_expired')), isTrue);
      expect(registro.esCallbackDeAuth(verificacion('#error_description=x')), isTrue);
      expect(registro.esCallbackDeAuth(Uri.parse('io.supabase.colportores://otra/cosa')), isFalse);
    });

    test('recuerda si el último link fue de recuperación, con o sin barra final', () {
      registro.esCallbackDeAuth(recuperacion('?code=abc'));
      expect(registro.ultimoEsRecuperacion, isTrue);

      registro.esCallbackDeAuth(
        Uri.parse('io.supabase.colportores://login-callback/recuperacion/'),
      );
      expect(registro.ultimoEsRecuperacion, isTrue);

      registro.esCallbackDeAuth(verificacion('#error_code=otp_expired'));
      expect(registro.ultimoEsRecuperacion, isFalse);
    });

    test('un enlace de recuperación de auth queda "en canje" hasta que alguien toma su resultado, '
        'una sola vez', () {
      expect(registro.tomarRecuperacionEnCanje(), isFalse);

      registro.esCallbackDeAuth(recuperacion('#error_code=otp_expired'));

      expect(registro.tomarRecuperacionEnCanje(), isTrue);
      expect(registro.tomarRecuperacionEnCanje(), isFalse);
    });

    test(
      'un link de verificación o uno de recuperación sin parámetros de auth no queda en canje',
      () {
        registro
          ..esCallbackDeAuth(verificacion('?code=abc'))
          ..esCallbackDeAuth(Uri.parse(ConfigSupabase.redirectRecuperacion));

        expect(registro.tomarRecuperacionEnCanje(), isFalse);
      },
    );
  });

  group('RegistroEnlacesAuth — enlace con código de un solo uso (token_hash)', () {
    const codigo = 'abc123';
    late DateTime ahora;
    late List<String> recibidos;

    setUp(() {
      ahora = DateTime.utc(2026, 11, 26, 10);
      registro = RegistroEnlacesAuth(ahora: () => ahora);
      recibidos = [];
    });

    test('el de recuperación con type=recovery no lo canjea supabase_flutter (el predicado da '
        'false) y llega al receptor', () {
      registro.recibirCodigos(recibidos.add);

      final deAuth = registro.esCallbackDeAuth(recuperacion('?token_hash=$codigo&type=recovery'));

      expect(deAuth, isFalse);
      expect(recibidos, [codigo]);
      expect(registro.ultimoEsRecuperacion, isTrue);
      expect(registro.tomarRecuperacionEnCanje(), isTrue);
    });

    test('con la barra final de la ruta también es de recuperación', () {
      registro.recibirCodigos(recibidos.add);

      registro.esCallbackDeAuth(
        Uri.parse('${ConfigSupabase.redirectRecuperacion}/?token_hash=$codigo&type=recovery'),
      );

      expect(recibidos, [codigo]);
    });

    test('un token_hash sin type=recovery, con otro type, o en la ruta de la verificación no es '
        'un código de recuperación: no se entrega', () {
      registro.recibirCodigos(recibidos.add);

      expect(registro.esCallbackDeAuth(recuperacion('?token_hash=$codigo')), isFalse);
      expect(registro.esCallbackDeAuth(recuperacion('?token_hash=$codigo&type=signup')), isFalse);
      expect(
        registro.esCallbackDeAuth(verificacion('verificado?token_hash=$codigo&type=recovery')),
        isFalse,
      );

      expect(recibidos, isEmpty);
      expect(registro.tomarRecuperacionEnCanje(), isFalse);
    });

    test('un enlace viejo con ?code= sigue siendo de auth y no pasa por el receptor', () {
      registro.recibirCodigos(recibidos.add);

      expect(registro.esCallbackDeAuth(recuperacion('?code=abc')), isTrue);

      expect(recibidos, isEmpty);
    });

    test('un código que llegó antes que el receptor (arranque en frío) se entrega al engancharlo, '
        'una sola vez', () {
      registro.esCallbackDeAuth(recuperacion('?token_hash=$codigo&type=recovery'));

      final desenganchar = registro.recibirCodigos(recibidos.add);
      expect(recibidos, [codigo]);

      desenganchar();
      registro.recibirCodigos(recibidos.add);
      expect(recibidos, [codigo]);
    });

    test('si llegaron varios antes del receptor entrega solo el último: cada pedido anula al '
        'anterior', () {
      registro
        ..esCallbackDeAuth(recuperacion('?token_hash=viejo&type=recovery'))
        ..esCallbackDeAuth(recuperacion('?token_hash=nuevo&type=recovery'))
        ..recibirCodigos(recibidos.add);

      expect(recibidos, ['nuevo']);
    });

    test('el mismo código dos veces seguidas es un solo toque; pasado el plazo, o con otro código, '
        'es un enlace nuevo', () {
      registro.recibirCodigos(recibidos.add);
      final enlace = recuperacion('?token_hash=$codigo&type=recovery');

      registro.esCallbackDeAuth(enlace);
      ahora = ahora.add(const Duration(seconds: 2));
      registro.esCallbackDeAuth(enlace);
      expect(recibidos, [codigo]);

      registro.esCallbackDeAuth(recuperacion('?token_hash=otro&type=recovery'));
      expect(recibidos, [codigo, 'otro']);

      ahora = ahora.add(RegistroEnlacesAuth.plazoDeUnMismoToque);
      registro.esCallbackDeAuth(recuperacion('?token_hash=otro&type=recovery'));
      expect(recibidos, [codigo, 'otro', 'otro']);
    });

    test('un token_hash vacío llega igual (la app lo trata como enlace vencido)', () {
      registro.recibirCodigos(recibidos.add);

      registro.esCallbackDeAuth(recuperacion('?token_hash=&type=recovery'));

      expect(recibidos, ['']);
    });

    test('desenganchar a un receptor viejo no desengancha al nuevo (volver atrás y reentrar)', () {
      final viejo = registro.recibirCodigos((_) {});
      registro.recibirCodigos(recibidos.add);

      viejo();
      registro.esCallbackDeAuth(recuperacion('?token_hash=$codigo&type=recovery'));

      expect(recibidos, [codigo]);
    });
  });

  test('hay una sola instancia para la app, la que engancha main.dart', () {
    expect(identical(RegistroEnlacesAuth.instancia, RegistroEnlacesAuth.instancia), isTrue);
  });
}
