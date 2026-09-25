import 'dart:async';

import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/motivo_expiracion.dart';
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
      // "Edge - fallo intermitente del backend" (HU-AUTH-001, issue #90): registro propio del
      // NetworkFailure con el status, sin PII (nunca nombre ni email) — el criterio de aceptación
      // lo pide aparte del genérico REGISTRO_FAIL.
      if (e is ServidorException && e.status != null && e.status! >= 500) {
        _log.warn(LogModulo.auth, 'REGISTRO_5XX', 'fallo intermitente del backend', {
          'status': e.status,
        });
      } else {
        _log.warn(LogModulo.auth, 'REGISTRO_FAIL', 'registro rechazado', {
          'codigo': failure.codigo,
        });
      }
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
      if (local != null) {
        // El proveedor renueva el JWT solo: si su sesión es del mismo usuario, esa es la vigente,
        // y reemplaza a la guardada (HU-AUTH-007, "Refresh transparente").
        final vigente = _sesionVigente(local);
        if (!identical(vigente, local)) await _local.guardarSesion(vigente);
        return Right(vigente.toEntity());
      }

      // Sin sesión local (p. ej. tras reiniciar la app): el proveedor la tiene persistida por su
      // cuenta (supabase_flutter, en el almacén seguro). No toca la red.
      final SesionModel? remota;
      try {
        remota = await _remote.obtenerSesionActual();
      } on AuthRemoteException catch (e) {
        _log.warn(LogModulo.auth, 'SESION_RESTAURAR_FAIL', 'no se pudo restaurar la sesión', {
          'codigo': _traducir(e).codigo,
        });
        return const Right(null);
      }
      if (remota == null) {
        if (!_remote.tomarVencimientoPorInactividad()) return const Right(null);
        _log.info(LogModulo.auth, 'SESION_EXPIRADA', 'sesión vencida por inactividad al arrancar', {
          'motivo': MotivoExpiracion.inactividad.name,
        });
        return const Left(FailureSesionExpiradaPorInactividad());
      }

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
      final guardada = await _local.leerSesion();
      var resultado = ResultadoCierreSesion.completo;
      if (guardada != null) {
        // Antes de `signOut`, que suelta la sesión del cliente: la que queda pendiente de revocar
        // tiene que llevar el token vigente, no el del login (#102).
        final sesion = _sesionVigente(guardada);
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
        'user_id': guardada?.usuarioId,
        'revocacion_pendiente': resultado == ResultadoCierreSesion.revocacionPendiente,
      });
      return Right(resultado);
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'LOGOUT_FAIL', 'no se pudo borrar la sesión', const {}, e, st);
      return Left(FailureInesperado(causa: e));
    }
  }

  /// La sesión que tiene el cliente del proveedor ahora, si es del mismo usuario que [guardada];
  /// si no, [guardada].
  ///
  /// `supabase_flutter` renueva el JWT solo (`autoRefreshToken`), así que el `accessToken` que se
  /// guardó en el login puede estar vencido o reemplazado: revocar ese más tarde no cerraría la
  /// sesión que sigue viva en el servidor. Se lee **sin refrescar ni tocar la red**: el logout no
  /// puede quedar esperando a la red (si matan la app en el medio, la sesión sobreviviría;
  /// revisión de #107). Si el cliente no la puede dar, se usa la guardada.
  SesionModel _sesionVigente(SesionModel guardada) {
    try {
      final actual = _remote.sesionEnElCliente();
      if (actual != null && actual.usuarioId == guardada.usuarioId) return actual;
    } on Object catch (e) {
      _log.debug(LogModulo.auth, 'LOGOUT_TOKEN_VIGENTE', 'se usa el token guardado', {
        'error': e.runtimeType.toString(),
      });
    }
    return guardada;
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
  Future<Either<Failure, Sesion>> confirmarPassword({
    required Sesion sesion,
    required String password,
  }) async {
    // Antes del login: después, el cliente ya tiene la sesión nueva.
    final reemplazada = _sesionVigente(SesionModel.fromEntity(sesion));
    final resultado = await iniciarSesion(email: sesion.email, password: password);
    if (resultado case Right(value: final nueva)
        when nueva.usuarioId == reemplazada.usuarioId &&
            nueva.accessToken != reemplazada.accessToken) {
      unawaited(_revocarReemplazada(reemplazada));
    }
    return resultado;
  }

  Future<void> _revocarReemplazada(SesionModel reemplazada) async {
    try {
      await _remote.revocarSesion(reemplazada.accessToken);
      _log.info(LogModulo.auth, 'SESION_REEMPLAZADA_REVOCADA', 'se revocó la sesión anterior', {
        'user_id': reemplazada.usuarioId,
      });
    } on Object catch (e) {
      // Best-effort: el usuario ya está adentro con la sesión nueva y no puede hacer nada con esto.
      final failure = switch (e) {
        final AuthRemoteException remota => _traducir(remota),
        _ => FailureInesperado(causa: e),
      };
      _log.warn(
        LogModulo.auth,
        'SESION_REEMPLAZADA_REVOCACION_FAIL',
        'la sesión anterior sigue viva en el servidor',
        {'user_id': reemplazada.usuarioId, 'codigo': failure.codigo},
      );
    }
  }

  /// El refresh en curso, si hay uno: las llamadas simultáneas lo comparten (HU-AUTH-007, "coordinar
  /// refresh único").
  Future<Either<Failure, Sesion>>? _renovacionEnCurso;

  @override
  Future<Either<Failure, Sesion>> renovarSesion() =>
      _renovacionEnCurso ??= _renovar().whenComplete(() => _renovacionEnCurso = null);

  Future<Either<Failure, Sesion>> _renovar() async {
    try {
      final sesion = await _remote.renovarSesion();
      await _local.guardarSesion(sesion);
      _log.info(LogModulo.auth, 'SESION_RENOVADA', 'JWT renovado', {'user_id': sesion.usuarioId});
      return Right(sesion.toEntity());
    } on SinConexionException {
      // Se mantiene la sesión anterior; el próximo request con red la renueva.
      _log.info(LogModulo.auth, 'SESION_RENOVAR_OFFLINE', 'sin red: se mantiene la sesión');
      return const Left(FailureSinConexion());
    } on SesionRevocadaException {
      _log.warn(LogModulo.auth, 'SESION_REVOCADA', 'el servidor ya no acepta la sesión');
      return const Left(FailureSesionRevocada());
    } on AuthRemoteException catch (e) {
      final failure = _traducir(e);
      _log.warn(LogModulo.auth, 'SESION_RENOVAR_FAIL', 'refresh rechazado', {
        'codigo': failure.codigo,
      });
      return Left(failure);
    } on Object catch (e, st) {
      _log.error(
        LogModulo.auth,
        'SESION_RENOVAR_FAIL',
        'error inesperado en refresh',
        const {},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Stream<MotivoExpiracion> get expiraciones => _remote.expiraciones;

  @override
  Future<Either<Failure, Unit>> expirarSesion(MotivoExpiracion motivo) async {
    try {
      final guardada = await _local.leerSesion();
      await _local.borrarSesion();
      // Ya se está atendiendo: que el próximo arranque no lo vuelva a avisar.
      if (motivo == MotivoExpiracion.inactividad) _remote.tomarVencimientoPorInactividad();
      // Si el cliente del proveedor todavía la tiene (vencida por inactividad con la app
      // abierta), se suelta sin esperar a la red: con red, además, se revoca.
      final enCliente = _sesionEnElCliente();
      if (enCliente != null) unawaited(_soltarDelCliente(enCliente));
      _log.info(LogModulo.auth, 'SESION_EXPIRADA', 'sesión descartada', {
        'user_id': guardada?.usuarioId,
        'motivo': motivo.name,
      });
      return const Right(unit);
    } on Object catch (e, st) {
      _log.error(
        LogModulo.auth,
        'SESION_EXPIRAR_FAIL',
        'no se pudo descartar la sesión',
        const {},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }

  SesionModel? _sesionEnElCliente() {
    try {
      return _remote.sesionEnElCliente();
    } on Object {
      return null;
    }
  }

  Future<void> _soltarDelCliente(SesionModel sesion) async {
    try {
      await _remote.cerrarSesion(sesion.accessToken);
    } on Object catch (e) {
      // Sin red o con el token ya rechazado: la copia local del proveedor ya se soltó igual.
      _log.debug(LogModulo.auth, 'SESION_SOLTAR', 'no se pudo revocar la sesión vencida', {
        'error': e.runtimeType.toString(),
      });
    }
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

  @override
  Stream<void> get verificacionesExitosas => _remote.verificacionesExitosas;

  static Failure _traducir(AuthRemoteException e) => switch (e) {
    CredencialesInvalidasException() => const FailureCredencialesInvalidas(),
    EmailYaRegistradoException() => const FailureEmailYaRegistrado(),
    SinConexionException() => const FailureSinConexion(),
    SesionRevocadaException() => const FailureSesionRevocada(),
    PasswordDebilException() => const FailureValidacion(
      campos: {'password': 'La contraseña es demasiado débil.'},
    ),
    // Solo los lanza la recuperación de contraseña (HU-AUTH-005), que tiene su propio repositorio:
    // acá no llegan, pero el switch es exhaustivo.
    PasswordIgualALaAnteriorException() => const FailureValidacion(
      campos: {'password': 'Tiene que ser distinta de la anterior.'},
    ),
    SesionDeRecuperacionVencidaException() => const FailureEnlaceRecuperacionVencido(),
    ServidorException(:final status, :final mensaje) =>
      mensaje == null
          ? FailureServidor(status: status)
          : FailureServidor(status: status, mensaje: mensaje),
  };
}
