import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/resultado_cierre_sesion.dart';
import '../repositories/auth_repository.dart';

/// HU-AUTH-006 — Cierre de sesión: revoca el JWT (o lo deja pendiente sin red) y borra la sesión
/// local. Los datos del teléfono se conservan; borrarlos es HU-AUTH-010.
final class CerrarSesionUseCase implements UseCase<ResultadoCierreSesion, NoParams> {
  const CerrarSesionUseCase(this._repository);

  final AuthRepository _repository;

  @override
  Future<Either<Failure, ResultadoCierreSesion>> call(NoParams params) =>
      _repository.cerrarSesion();
}
