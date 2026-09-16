// Test de la capa data: Dart puro, con los data sources en memoria.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resultado_registro.dart';
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
  Future<SesionModel?> registrar({
    required String nombre,
    required String apellido,
    required String cedula,
    required String email,
    required String password,
  }) async {
    throw Exception('boom');
  }

  @override
  Future<SesionModel> iniciarSesionConGoogle() async => throw Exception('boom');

  @override
  Future<SesionModel?> obtenerSesionActual() async => throw Exception('boom');

  @override
  Future<void> cerrarSesion(String accessToken) {
    throw UnimplementedError();
  }
}

/// Remoto que "recuerda" una sesión persistida por el proveedor (como supabase_flutter tras
/// reiniciar la app), o que falla al consultarla.
final class _RemoteConSesionRecordada implements AuthRemoteDataSource {
  _RemoteConSesionRecordada({this.recordada, this.falla});

  final SesionModel? recordada;
  final AuthRemoteException? falla;
  final AuthRemoteDataSourceEnMemoria _interno = AuthRemoteDataSourceEnMemoria(
    credenciales: const {},
  );

  @override
  Future<SesionModel?> obtenerSesionActual() async {
    if (falla != null) throw falla!;
    return recordada;
  }

  @override
  Future<SesionModel> iniciarSesionConGoogle() {
    if (falla != null) throw falla!;
    return _interno.iniciarSesionConGoogle();
  }

  @override
  Future<SesionModel> iniciarSesion({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<SesionModel?> registrar({
    required String nombre,
    required String apellido,
    required String cedula,
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> cerrarSesion(String accessToken) => throw UnimplementedError();
}

/// Remoto que devuelve una única excepción fija en `registrar` — para probar cómo el repositorio
/// traduce casos que el fake en memoria no modela (p. ej. contraseña débil).
final class _RemoteQueLanzaEnRegistrar implements AuthRemoteDataSource {
  _RemoteQueLanzaEnRegistrar(this.excepcion);

  final AuthRemoteException excepcion;

  @override
  Future<SesionModel> iniciarSesion({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<SesionModel?> registrar({
    required String nombre,
    required String apellido,
    required String cedula,
    required String email,
    required String password,
  }) async => throw excepcion;

  @override
  Future<SesionModel> iniciarSesionConGoogle() => throw UnimplementedError();

  @override
  Future<SesionModel?> obtenerSesionActual() => throw UnimplementedError();

  @override
  Future<void> cerrarSesion(String accessToken) => throw UnimplementedError();
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
        final r = resultado.getOrElse(() => throw StateError('esperaba Right'));
        expect(r.requiereVerificacion, isFalse);
        final sesion = r.sesion!;
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

        expect(resultado, const Left<Failure, ResultadoRegistro>(FailureEmailYaRegistrado()));
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

        expect(resultado, const Left<Failure, ResultadoRegistro>(FailureSinConexion()));
      });
    });

    group('dado que falta verificar el email (Confirm email activo)', () {
      test('cuando registra, devuelve ResultadoRegistro sin sesión y no persiste', () async {
        final remotePendiente = AuthRemoteDataSourceEnMemoria(
          credenciales: const {},
          requiereVerificacionAlRegistrar: true,
        );
        final repositoryPendiente = AuthRepositoryImpl(
          remotePendiente,
          local,
          logger: loggerMudo(),
        );

        final resultado = await repositoryPendiente.registrar(
          nombre: 'Bruno',
          apellido: 'Díaz',
          cedula: '12345678',
          email: 'bruno@example.com',
          password: 'Secreto123',
        );

        expect(resultado.isRight(), isTrue);
        final r = resultado.getOrElse(() => throw StateError('esperaba Right'));
        expect(r.requiereVerificacion, isTrue);
        expect(r.sesion, isNull);
        expect(r.email, 'bruno@example.com');
        expect(await local.leerSesion(), isNull);
      });

      test('cuando intenta entrar antes de confirmar, devuelve FailureServidor; después de '
          'confirmarEmail, entra normal', () async {
        final remotePendiente = AuthRemoteDataSourceEnMemoria(
          credenciales: const {},
          requiereVerificacionAlRegistrar: true,
        );
        final repositoryPendiente = AuthRepositoryImpl(
          remotePendiente,
          local,
          logger: loggerMudo(),
        );
        await repositoryPendiente.registrar(
          nombre: 'Bruno',
          apellido: 'Díaz',
          cedula: '12345678',
          email: 'bruno@example.com',
          password: 'Secreto123',
        );

        final antes = await repositoryPendiente.iniciarSesion(
          email: 'bruno@example.com',
          password: 'Secreto123',
        );
        expect(
          antes,
          const Left<Failure, Sesion>(
            FailureServidor(
              mensaje: 'Tenés que verificar tu correo antes de entrar. Revisá tu bandeja.',
            ),
          ),
        );

        remotePendiente.confirmarEmail('bruno@example.com');

        final despues = await repositoryPendiente.iniciarSesion(
          email: 'bruno@example.com',
          password: 'Secreto123',
        );
        expect(despues.isRight(), isTrue);
      });
    });

    group('dado que la contraseña es débil', () {
      test('cuando registra, devuelve FailureValidacion con el error en password', () async {
        final repositorioRoto = AuthRepositoryImpl(
          _RemoteQueLanzaEnRegistrar(const PasswordDebilException()),
          local,
          logger: loggerMudo(),
        );

        final resultado = await repositorioRoto.registrar(
          nombre: 'Bruno',
          apellido: 'Díaz',
          cedula: '12345678',
          email: 'bruno@example.com',
          password: 'debil',
        );

        expect(
          resultado,
          const Left<Failure, ResultadoRegistro>(
            FailureValidacion(campos: {'password': 'La contraseña es demasiado débil.'}),
          ),
        );
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

  group('AuthRepositoryImpl.iniciarSesionConGoogle', () {
    test('cuando el proveedor entra, devuelve la Sesion y la persiste localmente', () async {
      final resultado = await repository.iniciarSesionConGoogle();

      expect(resultado.isRight(), isTrue);
      final sesion = resultado.getOrElse(() => throw StateError('Left'));
      expect(sesion, isA<Sesion>().having((s) => s.runtimeType, 'tipo', Sesion));
      expect(sesion.email, AuthRemoteDataSourceEnMemoria.emailGoogle);
      expect(remote.llamadasIniciarSesionConGoogle, 1);
      expect(await local.leerSesion(), SesionModel.fromEntity(sesion));
    });

    test('cuando no hay conexión, devuelve FailureSinConexion y no persiste nada', () async {
      remote.simularSinConexion = true;

      final resultado = await repository.iniciarSesionConGoogle();

      expect(resultado, const Left<Failure, Sesion>(FailureSinConexion()));
      expect(await local.leerSesion(), isNull);
    });

    test('cuando el data source lanza algo no tipado, devuelve FailureInesperado', () async {
      final repo = AuthRepositoryImpl(
        _RemoteQueLanzaExcepcionGenerica(),
        local,
        logger: loggerMudo(),
      );

      final resultado = await repo.iniciarSesionConGoogle();

      expect(resultado.fold((f) => f, (_) => null), isA<FailureInesperado>());
    });

    test('un ServidorException con mensaje llega como FailureServidor con ese mensaje', () async {
      final repo = AuthRepositoryImpl(
        _RemoteConSesionRecordada(falla: const ServidorException(mensaje: 'No se completó')),
        local,
        logger: loggerMudo(),
      );

      final resultado = await repo.iniciarSesionConGoogle();

      expect(resultado, const Left<Failure, Sesion>(FailureServidor(mensaje: 'No se completó')));
    });
  });

  group('AuthRepositoryImpl.sesionActual', () {
    test('cuando no hubo login, devuelve Right(null)', () async {
      expect(await repository.sesionActual(), const Right<Failure, Sesion?>(null));
    });

    test(
      'sin sesión local pero con una recordada por el proveedor, la restaura y la persiste',
      () async {
        final recordada = SesionModel(
          usuarioId: '01920000-0000-7000-8000-000000000009',
          email: 'ana@example.com',
          accessToken: 'jwt-restaurado',
          expiraEn: DateTime.utc(2026, 9, 1, 13),
        );
        final repo = AuthRepositoryImpl(
          _RemoteConSesionRecordada(recordada: recordada),
          local,
          logger: loggerMudo(),
        );

        final resultado = await repo.sesionActual();

        expect(resultado.getOrElse(() => null), recordada.toEntity());
        expect(await local.leerSesion(), recordada);
      },
    );

    test(
      'si el proveedor no puede restaurarla (sin red), arranca deslogueado sin Failure',
      () async {
        final repo = AuthRepositoryImpl(
          _RemoteConSesionRecordada(falla: const SinConexionException()),
          local,
          logger: loggerMudo(),
        );

        expect(await repo.sesionActual(), const Right<Failure, Sesion?>(null));
      },
    );

    test('si leer la sesión explota, devuelve FailureInesperado', () async {
      final repo = AuthRepositoryImpl(
        _RemoteQueLanzaExcepcionGenerica(),
        local,
        logger: loggerMudo(),
      );

      final resultado = await repo.sesionActual();

      expect(resultado.fold((f) => f, (_) => null), isA<FailureInesperado>());
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
