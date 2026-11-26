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

  /// El turno del último pedido de cambio, que sigue en la fila hasta que su pedido contesta
  /// (aunque ya haya pasado el [tope]): un cambio nuevo ocupa la fila al llegar y espera al turno
  /// anterior antes de mandarse, así dos que esperan al mismo pedido varado salen de a uno, en
  /// orden, y uno que llega tarde nunca pisa a otro posterior. No termina con error: solo avisa
  /// que terminó.
  Future<void>? _enVuelo;

  /// Las cuentas cuyas otras sesiones quedaron sin cerrar. Atadas a la cuenta para que el login de
  /// otra persona en el mismo teléfono no la consuma, y un conjunto para que dos cambios seguidos
  /// de cuentas distintas (sin login en el medio) no se pisen la marca (QA de #556).
  final Set<String> _otrasSinCerrarDe = {};

  /// La cuenta del último cambio de contraseña: de ella habla [otrasSesionesSinCerrar], que
  /// responde la pantalla de éxito de ese cambio.
  String? _cuentaDelUltimoCambio;

  /// Supabase manda el mismo error para un enlace vencido y para uno ya usado: la app no adivina
  /// cuál de los dos es, y los dos salen como [EnlaceRecuperacion.vencido].
  @override
  Stream<EnlaceRecuperacion> get enlaces => _remote.enlacesRecuperacion;

  @override
  String? get usuarioId => _remote.usuarioDeLaRecuperacion;

  @override
  Future<Either<Failure, Unit>> actualizarPassword(String nueva) async {
    // El turno se ocupa antes de esperar, sin pasar por un `await`: el que llega después espera
    // a este, no al anterior.
    final turno = Completer<void>();
    final anterior = _enVuelo;
    _enVuelo = turno.future;
    var enElAire = false;
    try {
      await _esperarA(anterior);
      final pedido = _remote.actualizarPassword(nueva);
      enElAire = true;
      unawaited(
        pedido.then<void>(
          (_) => _soltarTurno(turno),
          onError: (Object _, StackTrace _) => _soltarTurno(turno),
        ),
      );
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
    } finally {
      // Si el pedido nunca llegó a salir, el turno no puede quedar tomado.
      if (!enElAire) _soltarTurno(turno);
    }
  }

  /// Un cambio de contraseña nuevo no sale hasta que el anterior contesta o pasa su [tope]: dos
  /// pedidos en el aire pueden llegar al servidor en el orden contrario y dejar la contraseña que
  /// la persona ya no quiere (QA de #542). Si el anterior no contesta ni así, el nuevo sale igual:
  /// la persona no puede quedar sin poder guardar.
  Future<void> _esperarA(Future<void>? anterior) async {
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

  void _soltarTurno(Completer<void> turno) {
    if (identical(_enVuelo, turno.future)) _enVuelo = null;
    if (!turno.isCompleted) turno.complete();
  }

  // `audit_log` todavía no existe: el evento de la HU queda en el log (como `local_data_wipe`).
  void _registrarCambio() =>
      _log.info(LogModulo.auth, 'password_reset_completed', 'contraseña actualizada');

  @override
  bool get otrasSesionesSinCerrar =>
      _cuentaDelUltimoCambio != null && _otrasSinCerrarDe.contains(_cuentaDelUltimoCambio);

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
    _cuentaDelUltimoCambio = cuenta;
    if (cuenta != null) {
      if (resultado.isLeft()) {
        _otrasSinCerrarDe.add(cuenta);
      } else {
        _otrasSinCerrarDe.remove(cuenta);
      }
    }
    return resultado;
  }

  @override
  Future<Either<Failure, Unit>> cerrarOtrasSesionesPendientes(String usuarioId) async {
    if (!_otrasSinCerrarDe.contains(usuarioId)) return const Right(unit);
    final resultado = await _sinMostrar(
      'RECUPERACION_REVOCAR_OTRAS_FAIL',
      'no se pudieron revocar las otras sesiones al volver a entrar',
      _remote.cerrarLasOtrasSesiones,
    );
    if (resultado.isRight()) _otrasSinCerrarDe.remove(usuarioId);
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
    // El rechazo del servidor por largo; el formulario ya corta antes (PoliticaPassword, #296).
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
