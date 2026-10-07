import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/estado_cuenta.dart';
import '../repositories/cuenta_repository.dart';

/// Parámetros de [ConsultarEstadoCuentaUseCase].
final class ConsultarEstadoCuentaParams extends Equatable {
  const ConsultarEstadoCuentaParams({
    required this.usuarioId,
    required this.admiteUltimoConocido,
    this.alLlegarTarde,
  });

  final String usuarioId;

  /// `true` al entrar o al reabrir la app: si no se puede consultar, rige el último estado que
  /// informó el backend. `false` al refrescar a mano: el usuario pidió saber si cambió, y un
  /// estado viejo lo engañaría.
  final bool admiteUltimoConocido;

  /// Con [admiteUltimoConocido]: se llama con el estado si el backend contesta bien pasado el
  /// límite de espera (la consulta ya se resolvió con lo que había). Quien llama decide si le sirve
  /// (#278).
  final void Function(EstadoCuenta estado)? alLlegarTarde;

  @override
  List<Object?> get props => [usuarioId, admiteUltimoConocido];
}

/// Estado de la cuenta (HU-AUTH-008). Siempre lo decide el backend: sin red, el último que
/// informó; si nunca informó ninguno, la falla (la app no inventa un estado).
///
/// Al entrar o reabrir la app (`admiteUltimoConocido`) el backend tiene [limiteAlEntrar] para
/// responder: si no llega, se lo trata como sin conexión y rige lo de arriba (el último estado
/// conocido o, si no hay, `FailureSinConexion`). Así el arranque nunca queda esperando sin salida
/// (vista 18, #278). Refrescar a mano no tiene tope: el colportor ve que está consultando y puede
/// irse a Configuración.
final class ConsultarEstadoCuentaUseCase
    implements UseCase<EstadoCuenta, ConsultarEstadoCuentaParams> {
  const ConsultarEstadoCuentaUseCase(
    this._repository, {
    this.limiteAlEntrar = limiteConsultaAlEntrar,
  });

  /// Lo mismo que se espera una posición del GPS antes de tratarla como sin señal (#267).
  static const limiteConsultaAlEntrar = Duration(seconds: 15);

  final CuentaRepository _repository;

  /// Cuánto se espera la respuesta del backend al entrar o reabrir la app.
  final Duration limiteAlEntrar;

  @override
  Future<Either<Failure, EstadoCuenta>> call(ConsultarEstadoCuentaParams params) async {
    final consultado = params.admiteUltimoConocido
        ? await _consultarConLimite(params)
        : await _repository.consultar(params.usuarioId);
    if (consultado.isRight() || !params.admiteUltimoConocido) return consultado;
    final ultimo = await _repository.ultimoConocido(params.usuarioId);
    return ultimo == null ? consultado : Right(ultimo);
  }

  /// La respuesta que llega pasado el límite no cambia lo que ya se resolvió: el repositorio igual
  /// la recuerda para el próximo arranque y, si hay quien la espere, se la pasa
  /// [ConsultarEstadoCuentaParams.alLlegarTarde].
  Future<Either<Failure, EstadoCuenta>> _consultarConLimite(ConsultarEstadoCuentaParams params) {
    final consulta = _repository.consultar(params.usuarioId);
    var vencio = false;
    final alLlegarTarde = params.alLlegarTarde;
    if (alLlegarTarde != null) {
      void entregarSiVencio(Either<Failure, EstadoCuenta> respuesta) {
        if (vencio) respuesta.fold((_) {}, alLlegarTarde);
      }

      unawaited(consulta.then<void>(entregarSiVencio, onError: (Object _) {}));
    }
    Either<Failure, EstadoCuenta> alVencer() {
      vencio = true;
      return const Left<Failure, EstadoCuenta>(FailureSinConexion());
    }

    return consulta.timeout(limiteAlEntrar, onTimeout: alVencer);
  }
}
