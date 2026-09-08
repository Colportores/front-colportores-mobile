import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/sesion.dart';
import '../repositories/auth_repository.dart';

/// Sesión persistida en el dispositivo, si sigue vigente. Una sesión vencida cuenta como ausente:
/// la renovación (sliding session, HU-AUTH-006) es responsabilidad del repositorio.
final class ObtenerSesionActualUseCase implements UseCase<Sesion?, NoParams> {
  const ObtenerSesionActualUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final AuthRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, Sesion?>> call(NoParams params) async {
    final resultado = await _repository.sesionActual();
    return resultado.map(
      (sesion) => sesion != null && sesion.estaVigente(ahora: _ahora()) ? sesion : null,
    );
  }
}
