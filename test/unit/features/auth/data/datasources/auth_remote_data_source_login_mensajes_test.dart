// Test de la capa data contra Supabase Auth mockeado (mocktail sobre GoTrueClient).
//
// QA de HU-AUTH-003 (issue #24) — refuerza `auth_remote_data_source_supabase_test.dart`: ese
// archivo (compartido, no se toca acá) verifica el mensaje de "email sin confirmar" con
// `contains('verificar tu correo')`, que no detecta un mensaje truncado o con texto de más
// (mismo error que el QA de registro dejó pasar con otros mensajes). Este archivo nuevo prueba
// el texto completo y exacto que ve el usuario, para la traducción real de Supabase (no el fake
// en memoria, que ya se prueba en `auth_repository_impl_test.dart`).
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source_supabase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../helpers/logger_mudo.dart';

class _MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  late _MockGoTrueClient auth;

  setUp(() {
    auth = _MockGoTrueClient();
    when(() => auth.onAuthStateChange).thenAnswer((_) => const Stream.empty());
  });

  group('AuthRemoteDataSourceSupabase.iniciarSesion — mensaje de cuenta no verificada', () {
    test('dado un email sin confirmar, lanza ServidorException con el texto exacto de la HU '
        '(no solo una parte)', () async {
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

      final dataSource = AuthRemoteDataSourceSupabase(auth, logger: loggerMudo());

      await expectLater(
        dataSource.iniciarSesion(email: 'ana@example.com', password: 'secreto123'),
        throwsA(
          isA<ServidorException>().having(
            (e) => e.mensaje,
            'mensaje',
            'Tenés que verificar tu correo antes de entrar. Revisá tu bandeja.',
          ),
        ),
      );
    });
  });
}
