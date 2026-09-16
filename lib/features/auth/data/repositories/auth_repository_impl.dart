import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/resultado_registro.dart';
import '../../domain/entities/sesion.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_data_source.dart';
import '../datasources/auth_remote_data_source.dart';
import '../models/sesion_model.dart';

/// Implementación de [AuthRepository]. Plantilla de referencia para los repositorios del proyecto:
///
/// - Orquesta data sources (remoto + local) y decide el orden: primero remoto, luego persiste.
/// - Traduce **toda** excepción de infraestructura a un [Failure]; nunca deja escapar una.
/// - Devuelve entidades de dominio (`toEntity()`), no modelos.
/// - Loguea solo UUIDs y códigos (convenciones §7.5).
///
/// Auth es la única feature cuya escritura no pasa por `sync_queue`: la sesión no es un dato de
/// negocio que se sincronice (ADR-006), es la credencial con la que se sincroniza.
final class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remote, this._local, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final AuthRemoteDataSource _remote;
  final AuthLocalDataSource _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, Sesion>> iniciarSesion({
    required String email,
    required String password,
  }) async {
    try {
      final sesion = await _remote.iniciarSesion(email: email, password: password);
      await _local.guardarSesion(sesion);
      _log.info(LogModulo.auth, 'LOGIN_OK', 'login exitoso', {'user_id': sesion.usuarioId});
      return Right(sesion.toEntity());
    } on AuthRemoteException catch (e) {
      final failure = _traducir(e);
      _log.warn(LogModulo.auth, 'LOGIN_FAIL', 'login rechazado', {'codigo': failure.codigo});
      return Left(failure);
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'LOGIN_FAIL', 'error inesperado en login', const {}, e, st);
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Future<Either<Failure, ResultadoRegistro>> registrar({
    required String nombre,
    required String apellido,
    required String cedula,
    required String email,
    required String password,
  }) async {
    try {
      final sesion = await _remote.registrar(
        nombre: nombre,
        apellido: apellido,
        cedula: cedula,
        email: email,
        password: password,
      );
      if (sesion == null) {
        _log.info(LogModulo.auth, 'REGISTRO_PENDIENTE', 'registro OK, falta verificar el email');
        return Right(ResultadoRegistro(sesion: null, email: email));
      }
      await _local.guardarSesion(sesion);
      _log.info(LogModulo.auth, 'REGISTRO_OK', 'registro exitoso', {'user_id': sesion.usuarioId});
      return Right(ResultadoRegistro(sesion: sesion.toEntity(), email: email));
    } on AuthRemoteException catch (e) {
      final failure = _traducir(e);
      _log.warn(LogModulo.auth, 'REGISTRO_FAIL', 'registro rechazado', {'codigo': failure.codigo});
      return Left(failure);
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'REGISTRO_FAIL', 'error inesperado en registro', const {}, e, st);
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Future<Either<Failure, Sesion>> iniciarSesionConGoogle() async {
    try {
      final sesion = await _remote.iniciarSesionConGoogle();
      await _local.guardarSesion(sesion);
      _log.info(LogModulo.auth, 'LOGIN_GOOGLE_OK', 'login con Google exitoso', {
        'user_id': sesion.usuarioId,
      });
      return Right(sesion.toEntity());
    } on AuthRemoteException catch (e) {
      final failure = _traducir(e);
      _log.warn(LogModulo.auth, 'LOGIN_GOOGLE_FAIL', 'login con Google rechazado', {
        'codigo': failure.codigo,
      });
      return Left(failure);
    } on Object catch (e, st) {
      _log.error(
        LogModulo.auth,
        'LOGIN_GOOGLE_FAIL',
        'error inesperado en Google',
        const {},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Future<Either<Failure, Sesion?>> sesionActual() async {
    try {
      final local = await _local.leerSesion();
      if (local != null) return Right(local.toEntity());

      // Sin sesión local (p. ej. tras reiniciar la app): el proveedor puede tenerla persistida
      // por su cuenta (supabase_flutter). Si no se puede consultar (sin red y token vencido),
      // se arranca deslogueado; la política de "sliding session" offline es HU-AUTH-006.
      final SesionModel? remota;
      try {
        remota = await _remote.obtenerSesionActual();
      } on AuthRemoteException catch (e) {
        _log.warn(LogModulo.auth, 'SESION_RESTAURAR_FAIL', 'no se pudo restaurar la sesión', {
          'codigo': _traducir(e).codigo,
        });
        return const Right(null);
      }
      if (remota == null) return const Right(null);

      await _local.guardarSesion(remota);
      _log.info(LogModulo.auth, 'SESION_RESTAURADA', 'sesión restaurada del proveedor', {
        'user_id': remota.usuarioId,
      });
      return Right(remota.toEntity());
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'SESION_LEER_FAIL', 'no se pudo leer la sesión', const {}, e, st);
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Future<Either<Failure, Unit>> cerrarSesion() async {
    final sesion = await _local.leerSesion();
    try {
      if (sesion != null) await _remote.cerrarSesion(sesion.accessToken);
    } on SinConexionException {
      // Sin red igual se cierra localmente; la revocación remota queda para HU-AUTH-010.
      _log.warn(LogModulo.auth, 'LOGOUT_OFFLINE', 'logout sin conexión, solo local');
    } on AuthRemoteException catch (e) {
      _log.warn(LogModulo.auth, 'LOGOUT_REMOTO_FAIL', 'logout remoto falló', {
        'codigo': _traducir(e).codigo,
      });
    }

    try {
      await _local.borrarSesion();
      _log.info(LogModulo.auth, 'LOGOUT_OK', 'sesión cerrada', {'user_id': sesion?.usuarioId});
      return const Right(unit);
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'LOGOUT_FAIL', 'no se pudo borrar la sesión', const {}, e, st);
      return Left(FailureInesperado(causa: e));
    }
  }

  static Failure _traducir(AuthRemoteException e) => switch (e) {
    CredencialesInvalidasException() => const FailureCredencialesInvalidas(),
    CuentaPendienteException() => const FailureCuentaPendiente(),
    EmailYaRegistradoException() => const FailureEmailYaRegistrado(),
    SinConexionException() => const FailureSinConexion(),
    PasswordDebilException() => const FailureValidacion(
      campos: {'password': 'La contraseña es demasiado débil.'},
    ),
    ServidorException(:final status, :final mensaje) =>
      mensaje == null
          ? FailureServidor(status: status)
          : FailureServidor(status: status, mensaje: mensaje),
  };
}
