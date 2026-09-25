import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/enlace_recuperacion.dart';
import '../../domain/entities/politica_password.dart';
import '../../domain/repositories/recuperacion_password_repository.dart';
import '../datasources/auth_remote_data_source.dart';
import '../datasources/recuperacion_password_remote_data_source.dart';

/// [RecuperacionPasswordRepository] sobre el remoto (HU-AUTH-005). Traduce las excepciones a
/// [Failure] y deja en el log lo que el usuario no puede resolver.
final class RecuperacionPasswordRepositoryImpl implements RecuperacionPasswordRepository {
  RecuperacionPasswordRepositoryImpl(this._remote, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final RecuperacionPasswordRemoteDataSource _remote;
  final AppLogger _log;

  /// La contraseña de un intento que se cortó sin respuesta: Supabase pudo haberlo aceptado. Si el
  /// reintento con la misma contraseña vuelve con "igual a la anterior", el primero sí entró y la
  /// operación es un éxito (HU-AUTH-005, caso borde "pérdida de conexión durante el cambio").
  /// Solo en memoria, y se suelta con cualquier respuesta del servidor.
  String? _enDuda;

  @override
  Stream<EnlaceRecuperacion> get enlaces => _remote.enlacesRecuperacion;

  @override
  Future<Either<Failure, Unit>> actualizarPassword(String nueva) async {
    try {
      await _remote.actualizarPassword(nueva);
      _enDuda = null;
      _registrarCambio();
      return const Right(unit);
    } on PasswordIgualALaAnteriorException catch (e) {
      final eraElIntentoCortado = nueva == _enDuda;
      _enDuda = null;
      if (!eraElIntentoCortado) return Left(_traducir(e));
      _registrarCambio();
      return const Right(unit);
    } on SinConexionException catch (e) {
      _enDuda = nueva;
      return Left(_traducir(e));
    } on AuthRemoteException catch (e) {
      _enDuda = null;
      return Left(_traducir(e));
    } on Object catch (e, st) {
      _log.error(
        LogModulo.auth,
        'RECUPERACION_FAIL',
        'no se pudo actualizar la contraseña',
        const {},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }

  // `audit_log` todavía no existe: el evento de la HU queda en el log (como `local_data_wipe`).
  void _registrarCambio() =>
      _log.info(LogModulo.auth, 'password_reset_completed', 'contraseña actualizada');

  @override
  Future<Either<Failure, Unit>> cerrarTodasLasSesiones() => _sinMostrar(
    'RECUPERACION_REVOCAR_FAIL',
    'no se pudieron revocar las sesiones tras cambiar la contraseña',
    _remote.cerrarTodasLasSesiones,
  );

  @override
  Future<Either<Failure, Unit>> abandonar() {
    _enDuda = null;
    return _sinMostrar(
      'RECUPERACION_ABANDONAR_FAIL',
      'no se pudo soltar la sesión de recuperación',
      _remote.abandonarRecuperacion,
    );
  }

  /// Para los pasos cuyo error el usuario no puede resolver: va al log y sale como `Left`, pero
  /// quien llama no lo muestra.
  Future<Either<Failure, Unit>> _sinMostrar(
    String op,
    String mensaje,
    Future<void> Function() accion,
  ) async {
    try {
      await accion();
      return const Right(unit);
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, op, mensaje, const {}, e, st);
      return Left(e is AuthRemoteException ? _traducir(e) : FailureInesperado(causa: e));
    }
  }

  static Failure _traducir(AuthRemoteException e) => switch (e) {
    SinConexionException() => const FailureSinConexion(),
    SesionDeRecuperacionVencidaException() => const FailureEnlaceRecuperacionVencido(),
    PasswordIgualALaAnteriorException() => const FailureValidacion(
      campos: {'password': 'Tiene que ser distinta de la anterior.'},
    ),
    PasswordDebilException() => const FailureValidacion(
      campos: {'password': PoliticaPassword.requisitos},
    ),
    ServidorException(:final status, :final mensaje) =>
      mensaje == null
          ? FailureServidor(status: status)
          : FailureServidor(status: status, mensaje: mensaje),
    CredencialesInvalidasException() ||
    EmailYaRegistradoException() => const FailureInesperado(),
  };
}
