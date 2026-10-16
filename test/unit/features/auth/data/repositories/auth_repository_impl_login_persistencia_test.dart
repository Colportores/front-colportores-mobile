// Test de la capa data: Dart puro, con los data sources en memoria.
//
// QA de HU-AUTH-003 (issue #24) — refuerza `auth_repository_impl_test.dart` (compartido, no se
// toca acá): ese archivo prueba que un login con credenciales inválidas no persiste sesión local,
// pero no repite esa misma verificación para "cuenta no verificada" ni "sin conexión". Una sesión
// persistida tras un login que en la UI se mostró como fallido dejaría a la app en un estado
// inconsistente (por ejemplo, `sesionActual()` devolviendo una sesión que el usuario nunca vio
// como válida). Este archivo cierra ese hueco para esos dos escenarios.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  group('AuthRepositoryImpl.iniciarSesion — no persiste sesión local cuando falla', () {
    test(
      'dado que la cuenta no verificó el email, cuando inicia sesión, no guarda nada en local',
      () async {
        final remote = AuthRemoteDataSourceEnMemoria(
          credenciales: const {},
          requiereVerificacionAlRegistrar: true,
        );
        final local = AuthLocalDataSourceEnMemoria();
        final repository = AuthRepositoryImpl(remote, local, logger: loggerMudo());
        await repository.registrar(
          nombre: 'Bruno',
          apellido: 'Díaz',
          cedula: '12345678',
          email: 'bruno@example.com',
          password: 'Secreto123',
        );

        final resultado = await repository.iniciarSesion(
          email: 'bruno@example.com',
          password: 'Secreto123',
        );

        expect(resultado.isLeft(), isTrue);
        expect(await local.leerSesion(), isNull);
      },
    );

    test('dado que no hay conexión, cuando inicia sesión, no guarda nada en local', () async {
      final remote = AuthRemoteDataSourceEnMemoria(
        credenciales: const {'ana@example.com': 'secreto123'},
      )..simularSinConexion = true;
      final local = AuthLocalDataSourceEnMemoria();
      final repository = AuthRepositoryImpl(remote, local, logger: loggerMudo());

      final resultado = await repository.iniciarSesion(
        email: 'ana@example.com',
        password: 'secreto123',
      );

      expect(resultado, const Left<Failure, Sesion>(FailureSinConexion()));
      expect(await local.leerSesion(), isNull);
    });
  });
}
