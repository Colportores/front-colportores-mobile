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
final class ConsultarEstadoCuentaUseCase
    implements UseCase<EstadoCuenta, ConsultarEstadoCuentaParams> {
  const ConsultarEstadoCuentaUseCase(this._repository);

  final CuentaRepository _repository;

  @override
  Future<Either<Failure, EstadoCuenta>> call(ConsultarEstadoCuentaParams params) async {
    final consultado = await _repository.consultar(params.usuarioId);
    if (consultado.isRight() || !params.admiteUltimoConocido) return consultado;
    final ultimo = await _repository.ultimoConocido(params.usuarioId);
    return ultimo == null ? consultado : Right(ultimo);
  }
}
