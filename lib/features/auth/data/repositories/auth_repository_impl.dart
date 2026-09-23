import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/resultado_cierre_sesion.dart';
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
  Future<Either<Failure, Unit>> solicitarRecuperacionPassword({required String email}) async {
    try {
      await _remote.solicitarRecuperacionPassword(email);
      _log.info(LogModulo.auth, 'RECUPERACION_SOLICITADA', 'solicitud de recuperación enviada');
      return const Right(unit);
    } on SinConexionException {
      // Sin red no se pudo ni intentar — esto sí es visible: la HU-AUTH-002 fija el mismo patrón
      // ("Servicio temporalmente no disponible..."), anti-enumeración no exige mentir acá.
      _log.warn(LogModulo.auth, 'RECUPERACION_SIN_CONEXION', 'solicitud sin conectividad');
      return const Left(FailureSinConexion());
    } on AuthRemoteException catch (e) {
      // HU-AUTH-004 (líneas 824-828, "Edge - rate limit"): el único caso además de "el email no
      // existe" (que Supabase ni siquiera reporta como error) que la HU pide enmascarar como
      // éxito — si no, un atacante distingue "ya gastaste el límite" de "se mandó". Supabase
      // reporta el rate limit siempre como 429 (ver AuthRemoteDataSourceSupabase._traducir: tanto
      // por over_email_send_rate_limit/over_request_rate_limit como por el fallback sin código).
      // Cualquier otro error (servidor caído, contrato roto, etc.) sí es visible: anti-
      // enumeración protege "el email existe" y el rate limit, no una falla genuina del
      // servicio — el usuario tiene que poder reintentar (mismo patrón que HU-AUTH-002).
      if (e is ServidorException && e.status == 429) {
        _log.warn(
          LogModulo.auth,
          'RECUPERACION_RATE_LIMIT',
          'rate limit de Supabase (enmascarado)',
        );
        return const Right(unit);
      }
      final failure = _traducir(e);
      _log.warn(LogModulo.auth, 'RECUPERACION_FAIL', 'solicitud de recuperación rechazada', {
        'codigo': failure.codigo,
      });
      return Left(failure);
    } on Object catch (e, st) {
      _log.error(
        LogModulo.auth,
        'RECUPERACION_FAIL',
        'error inesperado al solicitar recuperación',
        const {},
        e,
        st,
      );
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

  /// Sesión cuyo JWT no se pudo revocar por falta de red (HU-AUTH-006, "Logout sin conexión").
  ///
  /// Vive en el repositorio (que es `keepAlive`) y no en el data source local porque hoy ese data
  /// source también es en memoria (`main.dart`): cuando llegue el respaldado por `secure_storage`,
  /// la pendiente se persiste ahí para sobrevivir a un reinicio de la app.
  SesionModel? _revocacionPendiente;

  @override
  Future<Either<Failure, ResultadoCierreSesion>> cerrarSesion() async {
    // Todo adentro del `try`: una falla al leer la sesión o una excepción no prevista del remoto
    // no puede saltearse el log ni el borrado local (#54).
    try {
      final sesion = await _local.leerSesion();
      var resultado = ResultadoCierreSesion.completo;
      if (sesion != null) {
        try {
          await _remote.cerrarSesion(sesion.accessToken);
        } on SinConexionException {
          _revocacionPendiente = sesion;
          resultado = ResultadoCierreSesion.revocacionPendiente;
          _log.warn(LogModulo.auth, 'LOGOUT_OFFLINE', 'logout sin conexión, revocación pendiente', {
            'user_id': sesion.usuarioId,
          });
        } on Object catch (e, st) {
          // El servidor respondió con error (o algo no previsto): no hay nada que reintentar con
          // ese token. El usuario no puede hacer nada con esto, así que solo va al log.
          _log.error(
            LogModulo.auth,
            'LOGOUT_REMOTO_FAIL',
            'logout remoto falló',
            {'codigo': e is AuthRemoteException ? _traducir(e).codigo : 'INESPERADO'},
            e,
            st,
          );
        }
      }

      await _local.borrarSesion();
      _log.info(LogModulo.auth, 'LOGOUT_OK', 'sesión cerrada', {
        'user_id': sesion?.usuarioId,
        'revocacion_pendiente': resultado == ResultadoCierreSesion.revocacionPendiente,
      });
      return Right(resultado);
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'LOGOUT_FAIL', 'no se pudo borrar la sesión', const {}, e, st);
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Future<Either<Failure, Unit>> reintentarRevocacionPendiente() async {
    final pendiente = _revocacionPendiente;
    if (pendiente == null) return const Right(unit);
    try {
      await _remote.revocarSesion(pendiente.accessToken);
      _log.info(LogModulo.auth, 'LOGOUT_REVOCADO', 'revocación pendiente completada', {
        'user_id': pendiente.usuarioId,
      });
    } on SinConexionException {
      return const Left(FailureSinConexion());
    } on Object catch (e, st) {
      // El servidor rechazó el token (vencido o ya revocado): reintentar no cambia nada.
      _log.error(
        LogModulo.auth,
        'LOGOUT_REVOCACION_FAIL',
        'revocación pendiente rechazada',
        {'user_id': pendiente.usuarioId},
        e,
        st,
      );
    }
    // Solo si nadie la reemplazó mientras tanto (otro logout sin red durante el `await`).
    if (identical(_revocacionPendiente, pendiente)) _revocacionPendiente = null;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> reenviarVerificacion({required String email}) async {
    try {
      await _remote.reenviarVerificacion(email);
      _log.info(LogModulo.auth, 'VERIFICACION_REENVIADA', 'reenvío de verificación solicitado');
      return const Right(unit);
    } on AuthRemoteException catch (e) {
      final failure = _traducir(e);
      _log.warn(LogModulo.auth, 'VERIFICACION_REENVIO_FAIL', 'reenvío rechazado', {
        'codigo': failure.codigo,
      });
      return Left(failure);
    } on Object catch (e, st) {
      _log.error(
        LogModulo.auth,
        'VERIFICACION_REENVIO_FAIL',
        'error inesperado al reenviar',
        const {},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Stream<void> get erroresVerificacionEmail => _remote.erroresVerificacionEmail;

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
