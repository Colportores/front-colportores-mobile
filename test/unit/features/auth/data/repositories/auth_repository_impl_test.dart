// Test de la capa data: Dart puro, con los data sources en memoria.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/domain/entities/usuario.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

/// Remoto roto a propósito: para probar que `registrar` traduce cualquier excepción no tipada a
/// [FailureInesperado] (no solo las [AuthRemoteException] conocidas).
final class _RemoteQueLanzaExcepcionGenerica implements AuthRemoteDataSource {
  @override
  Future<SesionModel> iniciarSesion({required String email, required String password}) {
    throw UnimplementedError();
  }

  @override
  Future<SesionModel> registrar({
    required String nombre,
    required String apellido,
    required String cedula,
    required String email,
    required String password,
  }) async {
    throw Exception('boom');
  }

  @override
  Future<void> cerrarSesion(String accessToken) {
    throw UnimplementedError();
  }
}

void main() {
  late AuthRemoteDataSourceEnMemoria remote;
  late AuthLocalDataSourceEnMemoria local;
  late AuthRepositoryImpl repository;

  setUp(() {
    remote = AuthRemoteDataSourceEnMemoria(
      credenciales: const {'ana@example.com': 'secreto123'},
      cuentasPendientes: const {'pendiente@example.com'},
      ahora: () => DateTime.utc(2026, 9, 1, 12),
    );
    local = AuthLocalDataSourceEnMemoria();
    repository = AuthRepositoryImpl(remote, local, logger: loggerMudo());
  });

  group('AuthRepositoryImpl.iniciarSesion', () {
    group('dado que las credenciales son válidas', () {
      test('cuando inicia sesión, devuelve la Sesion y la persiste localmente', () async {
        final resultado = await repository.iniciarSesion(
          email: 'ana@example.com',
          password: 'secreto123',
        );

        expect(resultado.isRight(), isTrue);
        final sesion = resultado.getOrElse(() => throw StateError('esperaba Right'));
        expect(sesion.runtimeType, Sesion, reason: 'el dominio recibe entidades, no modelos');
        expect(sesion.email, 'ana@example.com');
        expect(sesion.estaVigente(ahora: DateTime.utc(2026, 9, 1, 12, 30)), isTrue);
        expect((await local.leerSesion())?.toEntity(), sesion);
      });
    });

    group('dado que las credenciales son inválidas', () {
      test('cuando inicia sesión, devuelve FailureCredencialesInvalidas y no persiste', () async {
        final resultado = await repository.iniciarSesion(
          email: 'ana@example.com',
          password: 'otra',
        );

        expect(resultado, const Left<Failure, Sesion>(FailureCredencialesInvalidas()));
        expect(await local.leerSesion(), isNull);
      });
    });

    group('dado que la cuenta está pendiente de aprobación', () {
      test('cuando inicia sesión, devuelve FailureCuentaPendiente', () async {
        final resultado = await repository.iniciarSesion(
          email: 'pendiente@example.com',
          password: 'loquesea1',
        );

        expect(resultado, const Left<Failure, Sesion>(FailureCuentaPendiente()));
      });
    });

    group('dado que no hay conexión', () {
      test('cuando inicia sesión, devuelve FailureSinConexion', () async {
        remote.simularSinConexion = true;

        final resultado = await repository.iniciarSesion(
          email: 'ana@example.com',
          password: 'secreto123',
        );

        expect(resultado, const Left<Failure, Sesion>(FailureSinConexion()));
      });
    });
  });

  group('AuthRepositoryImpl.registrar', () {
    group('dado un email nuevo', () {
      test('cuando registra, devuelve la Sesion, la persiste localmente y guarda el perfil en el '
          'fake remoto', () async {
        final resultado = await repository.registrar(
          nombre: 'Bruno',
          apellido: 'Díaz',
          cedula: '12345678',
          email: 'bruno@example.com',
          password: 'Secreto123',
        );

        expect(resultado.isRight(), isTrue);
        final sesion = resultado.getOrElse(() => throw StateError('esperaba Right'));
        expect(sesion.runtimeType, Sesion, reason: 'el dominio recibe entidades, no modelos');
        expect(sesion.email, 'bruno@example.com');
        expect((await local.leerSesion())?.toEntity(), sesion);
        expect(
          remote.usuariosRegistrados['bruno@example.com'],
          Usuario(
            id: sesion.usuarioId,
            nombre: 'Bruno',
            apellido: 'Díaz',
            cedula: '12345678',
            email: 'bruno@example.com',
          ),
        );
      });

      test('cuando registra y luego inicia sesión, entra con esas credenciales', () async {
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

        expect(resultado.isRight(), isTrue);
      });
    });

    group('dado un email ya registrado', () {
      test('cuando registra, devuelve FailureEmailYaRegistrado y no persiste', () async {
        final resultado = await repository.registrar(
          nombre: 'Ana',
          apellido: 'Pérez',
          cedula: '12345678',
          email: 'ana@example.com',
          password: 'OtraSecreta1',
        );

        expect(resultado, const Left<Failure, Sesion>(FailureEmailYaRegistrado()));
        expect(await local.leerSesion(), isNull);
      });
    });

    group('dado que no hay conexión', () {
      test('cuando registra, devuelve FailureSinConexion', () async {
        remote.simularSinConexion = true;

        final resultado = await repository.registrar(
          nombre: 'Bruno',
          apellido: 'Díaz',
          cedula: '12345678',
          email: 'bruno@example.com',
          password: 'Secreto123',
        );

        expect(resultado, const Left<Failure, Sesion>(FailureSinConexion()));
      });
    });

    group('dado un error inesperado del data source', () {
      test('cuando registra, devuelve FailureInesperado en vez de dejarla escapar', () async {
        final repositorioRoto = AuthRepositoryImpl(
          _RemoteQueLanzaExcepcionGenerica(),
          local,
          logger: loggerMudo(),
        );

        final resultado = await repositorioRoto.registrar(
          nombre: 'Bruno',
          apellido: 'Díaz',
          cedula: '12345678',
          email: 'bruno@example.com',
          password: 'Secreto123',
        );

        expect(resultado.isLeft(), isTrue);
        final failure = resultado.swap().getOrElse(() => throw StateError('esperaba Left'));
        expect(failure, isA<FailureInesperado>());
      });
    });
  });

  group('AuthRepositoryImpl.sesionActual', () {
    test('cuando no hubo login, devuelve Right(null)', () async {
      expect(await repository.sesionActual(), const Right<Failure, Sesion?>(null));
    });

    test('cuando hubo login, devuelve la sesión guardada', () async {
      await repository.iniciarSesion(email: 'ana@example.com', password: 'secreto123');

      final resultado = await repository.sesionActual();

      expect(resultado.getOrElse(() => null)?.email, 'ana@example.com');
    });
  });

  group('AuthRepositoryImpl.cerrarSesion', () {
    setUp(() async {
      await repository.iniciarSesion(email: 'ana@example.com', password: 'secreto123');
    });

    test('cuando hay conexión, cierra remoto y borra la sesión local', () async {
      final resultado = await repository.cerrarSesion();

      expect(resultado, const Right<Failure, Unit>(unit));
      expect(remote.llamadasCerrarSesion, 1);
      expect(await local.leerSesion(), isNull);
    });

    test('cuando no hay conexión, igual borra la sesión local', () async {
      remote.simularSinConexion = true;

      final resultado = await repository.cerrarSesion();

      expect(resultado, const Right<Failure, Unit>(unit));
      expect(await local.leerSesion(), isNull);
    });
  });
}
