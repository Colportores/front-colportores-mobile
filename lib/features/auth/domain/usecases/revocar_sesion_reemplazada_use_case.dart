import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/sesion.dart';
import '../repositories/auth_repository.dart';

/// HU-AUTH-009 (revisión del PR #130, N3): confirmar la contraseña de una sesión restaurada es un
/// login nuevo, y la sesión anterior quedaría viva en el servidor aunque el teléfono ya no la use.
/// La revoca, solo a ella. Best-effort, como `ReintentarRevocacionPendienteUseCase`: si falla, el
/// usuario no puede hacer nada con eso.
final class RevocarSesionReemplazadaUseCase implements UseCase<Unit, Sesion> {
  const RevocarSesionReemplazadaUseCase(this._repository);

  final AuthRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(Sesion reemplazada) =>
      _repository.revocarSesionReemplazada(reemplazada);
}
