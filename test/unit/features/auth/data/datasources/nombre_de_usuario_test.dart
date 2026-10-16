// El nombre que la sesión de Supabase trae en `user_metadata` (#243): de ahí sale «Buen trabajo,
// <nombre>». El registro lo manda en `data: {nombre, apellido, cedula}`.
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source_supabase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? nombre(Map<String, dynamic>? meta) => AuthRemoteDataSourceSupabase.nombreDeUsuario(meta);

  test('una cuenta registrada con email trae el nombre', () {
    expect(nombre({'nombre': 'Lucía', 'apellido': 'Silva', 'cedula': '1.234.567-8'}), 'Lucía');
  });

  test('el nombre se recorta: los espacios sobrantes no llegan al saludo', () {
    expect(nombre({'nombre': '  Lucía \n'}), 'Lucía');
  });

  test('una cuenta cuyo trigger dejó el nombre vacío queda sin nombre', () {
    expect(nombre({'nombre': ''}), isNull);
    expect(nombre({'nombre': '   '}), isNull);
    expect(nombre({'full_name': 'Lucía Silva', 'avatar_url': 'https://x'}), isNull);
  });

  test('sin metadata, o con un dato que no es texto, queda sin nombre', () {
    expect(nombre(null), isNull);
    expect(nombre({}), isNull);
    expect(nombre({'nombre': 42}), isNull);
    expect(nombre({'nombre': null}), isNull);
  });
}
