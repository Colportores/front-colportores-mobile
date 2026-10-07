import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/estado_cuenta.dart';
import '../repositories/cuenta_repository.dart';

/// Parámetros de [ConsultarEstadoCuentaUseCase].
final class ConsultarEstadoCuentaParams extends Equatable {
  const ConsultarEstadoCuentaParams({required this.usuarioId, required this.admiteUltimoConocido});

  final String usuarioId;

  /// `true` al entrar o al reabrir la app: si no se puede consultar, rige el último estado que
  /// informó el backend. `false` al refrescar a mano: el usuario pidió saber si cambió, y un
  /// estado viejo lo engañaría.
  final bool admiteUltimoConocido;

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
        ? await _consultarConLimite(params.usuarioId)
        : await _repository.consultar(params.usuarioId);
    if (consultado.isRight() || !params.admiteUltimoConocido) return consultado;
    final ultimo = await _repository.ultimoConocido(params.usuarioId);
    return ultimo == null ? consultado : Right(ultimo);
  }

  /// La respuesta que llega pasado el límite no cambia lo que ya se resolvió: el repositorio igual
  /// la recuerda para el próximo arranque, y «Reintentar» consulta de nuevo.
  Future<Either<Failure, EstadoCuenta>> _consultarConLimite(String usuarioId) => _repository
      .consultar(usuarioId)
      .timeout(
        limiteAlEntrar,
        onTimeout: () => const Left<Failure, EstadoCuenta>(FailureSinConexion()),
      );
}
