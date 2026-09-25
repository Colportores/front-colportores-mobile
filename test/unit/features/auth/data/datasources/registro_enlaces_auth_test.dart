// De qué flujo es cada deep link de auth (HU-AUTH-005). Dart puro.
import 'package:colportores_mobile/core/config/config_supabase.dart';
import 'package:colportores_mobile/features/auth/data/datasources/registro_enlaces_auth.dart';
import 'package:test/test.dart';

void main() {
  late RegistroEnlacesAuth registro;

  setUp(() => registro = RegistroEnlacesAuth());

  Uri recuperacion(String parametros) =>
      Uri.parse('${ConfigSupabase.redirectRecuperacion}$parametros');
  Uri verificacion(String parametros) => Uri.parse('${ConfigSupabase.redirectOAuth}$parametros');

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

  test('hay una sola instancia para la app, la que engancha main.dart', () {
    expect(identical(RegistroEnlacesAuth.instancia, RegistroEnlacesAuth.instancia), isTrue);
  });
}
