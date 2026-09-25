// Si la cuenta de una sesión de Supabase entra con contraseña (revisión del PR #130): de eso depende
// que la DB local se proteja con un envoltorio por contraseña (ADR-006).
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source_supabase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool entra(Map<String, dynamic> meta) => AuthRemoteDataSourceSupabase.entraConPassword(meta);

  test('una cuenta de email, sí', () {
    expect(
      entra({
        'provider': 'email',
        'providers': ['email'],
      }),
      isTrue,
    );
  });

  test('una cuenta de Google, no', () {
    expect(
      entra({
        'provider': 'google',
        'providers': ['google'],
      }),
      isFalse,
    );
  });

  test('una cuenta de Google que después creó una contraseña, sí', () {
    expect(
      entra({
        'provider': 'google',
        'providers': ['google', 'email'],
      }),
      isTrue,
    );
  });

  test('sin la lista de proveedores, mira el principal', () {
    expect(entra({'provider': 'google'}), isFalse);
    expect(entra({'provider': 'email'}), isTrue);
  });

  test('sin información, ante la duda, sí: se pide la contraseña', () {
    expect(entra({}), isTrue);
  });
}
