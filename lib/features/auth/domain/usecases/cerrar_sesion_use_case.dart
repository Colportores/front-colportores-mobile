import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../repositories/auth_repository.dart';

/// HU-AUTH-005 — Cierre de sesión. La política de borrado local de datos (HU-AUTH-010) se
/// resuelve aparte; acá solo se invalida la sesión.
final class CerrarSesionUseCase implements UseCase<Unit, NoParams> {
  const CerrarSesionUseCase(this._repository);

  final AuthRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) => _repository.cerrarSesion();
}
