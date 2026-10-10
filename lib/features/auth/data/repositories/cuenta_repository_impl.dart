import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/generacion_datos_locales.dart';
import '../../domain/entities/estado_cuenta.dart';
import '../../domain/repositories/cuenta_repository.dart';
import '../datasources/auth_remote_data_source.dart';
import '../datasources/estado_cuenta_local_data_source.dart';
import '../datasources/estado_cuenta_remote_data_source.dart';

/// [CuentaRepository] sobre el BFF, recordando en el equipo el último estado que informó
/// (HU-AUTH-008), para que el colportor que abre la app sin señal no quede afuera.
///
/// Una respuesta que llega tarde (pasó el tope de 15 s de la pantalla) no se recuerda si en el medio
/// cambió quién tiene la sesión o se borraron los datos del teléfono (#319): el lugar donde se
/// recuerda es uno solo y no lleva más que el estado de una cuenta.
final class CuentaRepositoryImpl implements CuentaRepository {
  /// [usuarioEnSesion] es el usuario que tiene la sesión ahora (`null` si nadie) y [generacion] la
  /// cuenta de los borrados de datos locales; sin ellas, la respuesta se recuerda siempre.
  CuentaRepositoryImpl(
    this._remote,
    this._local, {
    this._usuarioEnSesion,
    this._generacion,
    AppLogger? logger,
    DateTime Function()? ahora,
  }) : _log = logger ?? AppLogger.instance,
       _ahora = ahora ?? DateTime.now;

  final EstadoCuentaRemoteDataSource _remote;
  final EstadoCuentaLocalDataSource _local;
  final String? Function()? _usuarioEnSesion;
  final GeneracionDatosLocales? _generacion;
  final AppLogger _log;
  final DateTime Function() _ahora;
  final _ultimaConsulta = <String, DateTime>{};

  /// Cuántas consultas se pidieron: cada una lleva su número, por el orden en que se pidió.
  int _pedidos = 0;

  /// El número de la consulta más nueva que ya contestó bien, por colportor.
  final _ultimaContestada = <String, int>{};

  @override
  Future<Either<Failure, EstadoCuenta>> consultar(String usuarioId) async {
    final pedido = ++_pedidos;
    final generacionAlPedir = _generacion?.valor;
    final EstadoCuenta estado;
    try {
      estado = await _remote.consultar();
    } on SinConexionException {
      return const Left(FailureSinConexion());
    } on ServidorException catch (e) {
      _log.warn(LogModulo.auth, 'ESTADO_CUENTA_FAIL', 'el BFF respondió con error', {
        'status': e.status,
      });
      final mensaje = e.mensaje;
      return Left(
        mensaje == null
            ? FailureServidor(status: e.status)
            : FailureServidor(status: e.status, mensaje: mensaje),
      );
    } on Object catch (e, st) {
      _log.error(
        LogModulo.auth,
        'ESTADO_CUENTA_FAIL',
        'no se pudo consultar el estado de cuenta',
        const {},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }

    // Una respuesta lenta puede llegar cuando ya no es de esta sesión: la persona borró los datos
    // locales o entró otra cuenta en el mismo teléfono. Recordarla reescribiría lo borrado o dejaría
    // el estado de otra cuenta en el único lugar donde se recuerda (#319). Se decide antes de
    // cualquier `await`, como lo de abajo.
    if (_cambioElContexto(usuarioId, generacionAlPedir)) {
      _log.info(LogModulo.auth, 'ESTADO_CUENTA_DESCARTADO', 'la sesión o los datos cambiaron', {
        'user_id': usuarioId,
      });
      return Right(estado);
    }
    // Gana la consulta pedida más tarde: la respuesta de una más vieja que llega después (pasó el
    // tope y la persona reintentó) trae lo que el backend sabía antes. Recordarla pisaría el estado
    // más nuevo en el próximo arranque sin red (QA #278). Se decide antes de cualquier `await`.
    if ((_ultimaContestada[usuarioId] ?? 0) > pedido) {
      _log.info(LogModulo.auth, 'ESTADO_CUENTA_VIEJO', 'respuesta de una consulta más vieja', {
        'user_id': usuarioId,
      });
      return Right(estado);
    }
    _ultimaContestada[usuarioId] = pedido;
    try {
      await _local.guardar(usuarioId, estado);
    } on Object catch (e, st) {
      // El estado se consultó bien: que no se pueda recordar solo pesa en un arranque sin red.
      _log.error(
        LogModulo.auth,
        'ESTADO_CUENTA_GUARDAR_FAIL',
        'no se pudo recordar el estado de cuenta',
        const {},
        e,
        st,
      );
    }
    _ultimaConsulta[usuarioId] = _ahora();
    _log.info(LogModulo.auth, 'ESTADO_CUENTA', 'estado de cuenta consultado', {
      'user_id': usuarioId,
      'estado': estado.name,
    });
    return Right(estado);
  }

  /// Si desde que se pidió la consulta de [usuarioId] otra cuenta tomó la sesión (o nadie la tiene)
  /// o se borraron los datos locales ([generacionAlPedir] ya no es la de ahora).
  bool _cambioElContexto(String usuarioId, int? generacionAlPedir) {
    final generacion = _generacion;
    if (generacion != null && generacion.valor != generacionAlPedir) return true;
    final usuarioEnSesion = _usuarioEnSesion;
    return usuarioEnSesion != null && usuarioEnSesion() != usuarioId;
  }

  @override
  Future<EstadoCuenta?> ultimoConocido(String usuarioId) async {
    try {
      return await _local.leer(usuarioId);
    } on Object catch (e) {
      _log.warn(LogModulo.auth, 'ESTADO_CUENTA_LEER_FAIL', 'no se pudo leer el último estado', {
        'error': e.runtimeType.toString(),
      });
      return null;
    }
  }

  @override
  DateTime? ultimaConsultaExitosa(String usuarioId) => _ultimaConsulta[usuarioId];
}
