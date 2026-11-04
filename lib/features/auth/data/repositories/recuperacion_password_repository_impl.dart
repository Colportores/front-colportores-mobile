import 'dart:async';

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
  RecuperacionPasswordRepositoryImpl(this._remote, {AppLogger? logger, this.tope = topePorDefecto})
    : _log = logger ?? AppLogger.instance;

  /// Lo que se espera la respuesta del servidor antes de dar el paso por cortado (QA #224): sin
  /// tope, una señal que se corta a mitad dejaba «Guardando…» para siempre y el atrás bloqueado.
  /// Son 15 s, el mismo número con que se espera la respuesta de autenticación (`limiteConsultaAlEntrar`;
  /// decisión del 29/10 en #542). Rige también para revocar y abandonar.
  static const topePorDefecto = Duration(seconds: 15);

  final RecuperacionPasswordRemoteDataSource _remote;
  final AppLogger _log;

  /// Ver [topePorDefecto].
  final Duration tope;

  /// La contraseña de un intento que se cortó sin respuesta: Supabase pudo haberlo aceptado. Si el
  /// reintento con la misma contraseña vuelve con "igual a la anterior", el primero sí entró y la
  /// operación es un éxito (HU-AUTH-005, caso borde "pérdida de conexión durante el cambio").
  /// Solo en memoria, y se suelta con cualquier respuesta del servidor.
  String? _enDuda;

  /// El último pedido de cambio que sigue en el aire (aunque ya haya pasado el [tope]): un cambio
  /// nuevo lo espera antes de mandarse, así uno que llega tarde nunca pisa a otro posterior. No
  /// termina con error: solo avisa que terminó.
  Future<void>? _enVuelo;

  /// La cuenta cuyas otras sesiones quedaron sin cerrar, o `null` si no hay nada pendiente. Atada
  /// a la cuenta para que el login de otra persona en el mismo teléfono no la consuma.
  String? _otrasSinCerrarDe;

  /// Supabase manda el mismo error para un enlace vencido y para uno ya usado: la app no adivina
  /// cuál de los dos es, y los dos salen como [EnlaceRecuperacion.vencido].
  @override
  Stream<EnlaceRecuperacion> get enlaces => _remote.enlacesRecuperacion;

  @override
  String? get usuarioId => _remote.usuarioDeLaRecuperacion;

  @override
  Future<Either<Failure, Unit>> actualizarPassword(String nueva) async {
    await _esperarAlPedidoAnterior();
    try {
      final pedido = _remote.actualizarPassword(nueva);
      late final Future<void> aviso;
      aviso = pedido.then<void>(
        (_) => _soltarEnVuelo(aviso),
        onError: (Object _, StackTrace _) => _soltarEnVuelo(aviso),
      );
      _enVuelo = aviso;
      await pedido.timeout(tope);
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
    } on TimeoutException {
      // Sin respuesta: igual que un corte de red. Supabase pudo haber aplicado el cambio, así que
      // el reintento con la misma contraseña se resuelve con `_enDuda`.
      _enDuda = nueva;
      _log.warn(
        LogModulo.auth,
        'RECUPERACION_TIMEOUT',
        'el servidor no respondió al cambiar la contraseña',
      );
      return const Left(FailureSinConexion());
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

  /// Un cambio de contraseña nuevo no sale hasta que el anterior contesta o pasa su [tope]: dos
  /// pedidos en el aire pueden llegar al servidor en el orden contrario y dejar la contraseña que
  /// la persona ya no quiere (QA de #542). Si el anterior no contesta ni así, el nuevo sale igual:
  /// la persona no puede quedar sin poder guardar.
  Future<void> _esperarAlPedidoAnterior() async {
    final anterior = _enVuelo;
    if (anterior == null) return;
    try {
      await anterior.timeout(tope);
    } on TimeoutException {
      _log.warn(
        LogModulo.auth,
        'RECUPERACION_PEDIDO_ANTERIOR',
        'el pedido anterior sigue sin contestar; se manda el nuevo',
      );
    }
  }

  void _soltarEnVuelo(Future<void> aviso) {
    if (identical(_enVuelo, aviso)) _enVuelo = null;
  }

  // `audit_log` todavía no existe: el evento de la HU queda en el log (como `local_data_wipe`).
  void _registrarCambio() =>
      _log.info(LogModulo.auth, 'password_reset_completed', 'contraseña actualizada');

  @override
  bool get otrasSesionesSinCerrar => _otrasSinCerrarDe != null;

  @override
  Future<Either<Failure, Unit>> cerrarTodasLasSesiones() async {
    // Antes de revocar: la revocación global suelta la sesión de recuperación y con ella el id.
    final cuenta = usuarioId;
    final resultado = await _sinMostrar(
      'RECUPERACION_REVOCAR_FAIL',
      'no se pudieron revocar las sesiones tras cambiar la contraseña',
      _remote.cerrarTodasLasSesiones,
    );
    // Si no contestó, los otros teléfonos pueden seguir adentro: queda para decírselo a la persona
    // y reintentar al próximo login (decisión del 29/10 en #542).
    _otrasSinCerrarDe = resultado.isLeft() ? cuenta : null;
    return resultado;
  }

  @override
  Future<Either<Failure, Unit>> cerrarOtrasSesionesPendientes(String usuarioId) async {
    if (_otrasSinCerrarDe != usuarioId) return const Right(unit);
    final resultado = await _sinMostrar(
      'RECUPERACION_REVOCAR_OTRAS_FAIL',
      'no se pudieron revocar las otras sesiones al volver a entrar',
      _remote.cerrarLasOtrasSesiones,
    );
    if (resultado.isRight() && _otrasSinCerrarDe == usuarioId) _otrasSinCerrarDe = null;
    return resultado;
  }

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
      await accion().timeout(tope);
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
    // Solo traduce el rechazo del servidor; el tope en el formulario de la vista 15 es #296.
    PasswordDemasiadoLargaException() => const FailureValidacion(
      campos: {'password': PoliticaPassword.demasiadoLarga},
    ),
    ServidorException(:final status, :final mensaje) =>
      mensaje == null
          ? FailureServidor(status: status)
          : FailureServidor(status: status, mensaje: mensaje),
    // No son de este flujo: la revocada solo sale de renovar la sesión (HU-AUTH-007).
    CredencialesInvalidasException() ||
    EmailYaRegistradoException() ||
    EmailInvalidoException() ||
    EmailNoConfirmadoException() ||
    SesionRevocadaException() => const FailureInesperado(),
  };
}
