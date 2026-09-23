// Test del data source real (Supabase) enfocado en el hueco señalado en la revisión del PR #82
// (#46), retomado en el comentario del issue #48: la anti-enumeración de HU-AUTH-004 depende de
// que un rate limit *real* de Supabase (un `AuthApiException` con `code: over_email_send_rate_limit`
// y el `statusCode` que Supabase realmente manda) termine, después de `_traducir()`, como
// `ServidorException` con `status == 429` — es lo único que `AuthRepositoryImpl.
// solicitarRecuperacionPassword` mira para decidir si enmascara como éxito.
//
// `auth_remote_data_source_supabase_test.dart` (compartido, no se toca en este issue) ya cubre
// `solicitarRecuperacionPassword` pero solo mirando `.mensaje` de la excepción traducida — nunca
// `.status`. Este archivo nuevo cierra ese hueco de punta a punta: mock de `GoTrueClient` con la
// excepción real de Supabase, sin armar el `ServidorException` a mano (a diferencia del fake que
// usan los tests de repositorio y widget).
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source_supabase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../helpers/logger_mudo.dart';

class _MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  late _MockGoTrueClient auth;

  AuthRemoteDataSourceSupabase dataSource() =>
      AuthRemoteDataSourceSupabase(auth, logger: loggerMudo());

  setUp(() {
    auth = _MockGoTrueClient();
  });

  group(
    'AuthRemoteDataSourceSupabase.solicitarRecuperacionPassword — rate limit real de Supabase',
    () {
      test('dado un AuthApiException con code "over_email_send_rate_limit" y statusCode "429" '
          '(el que Supabase realmente manda), lanza ServidorException con status == 429', () {
        when(
          () => auth.resetPasswordForEmail(any(), redirectTo: any(named: 'redirectTo')),
        ).thenThrow(
          const AuthApiException(
            'Email rate limit exceeded',
            statusCode: '429',
            code: 'over_email_send_rate_limit',
          ),
        );

        expect(
          () => dataSource().solicitarRecuperacionPassword('ana@example.com'),
          throwsA(isA<ServidorException>().having((e) => e.status, 'status', 429)),
        );
      });
    },
  );
}
