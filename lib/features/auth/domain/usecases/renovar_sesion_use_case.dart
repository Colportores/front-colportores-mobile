import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/sesion.dart';
import '../repositories/auth_repository.dart';

/// Renueva el JWT (HU-AUTH-007). Es el único punto de refresh que usa el resto de la app: el
/// motor de sync lo llama ante un `401` y reintenta el mismo job (ADR-007). Ver
/// [AuthRepository.renovarSesion] para los resultados.
final class RenovarSesionUseCase implements UseCase<Sesion, NoParams> {
  const RenovarSesionUseCase(this._repository);

  final AuthRepository _repository;

  @override
  Future<Either<Failure, Sesion>> call(NoParams params) => _repository.renovarSesion();
}
