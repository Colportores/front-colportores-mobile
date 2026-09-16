// Sin --dart-define (tests, CI sin variables) la app tiene que caer a los fakes en memoria.
import 'package:colportores_mobile/core/config/config_supabase.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConfigSupabase', () {
    test('sin SUPABASE_URL ni SUPABASE_ANON_KEY no está configurada', () {
      expect(ConfigSupabase.url, isEmpty);
      expect(ConfigSupabase.anonKey, isEmpty);
      expect(ConfigSupabase.configurada, isFalse);
    });

    test('el deep link de OAuth es el que declara AndroidManifest.xml', () {
      expect(ConfigSupabase.redirectOAuth, 'io.supabase.colportores://login-callback/');
      expect(ConfigSupabase.redirectOAuth, startsWith('io.supabase.colportores://login-callback'));
    });
  });

  group('authRemoteDataSourceProvider', () {
    test('dado que Supabase no está configurado, elige el fake en memoria con la cuenta demo', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(authRemoteDataSourceProvider), isA<AuthRemoteDataSourceEnMemoria>());
    });
  });
}
