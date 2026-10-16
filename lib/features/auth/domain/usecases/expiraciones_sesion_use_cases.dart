import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/motivo_expiracion.dart';
import '../repositories/auth_repository.dart';

/// Cada vez que la sesión termina sin que el usuario lo pida (HU-AUTH-007).
final class ObservarExpiracionesSesionUseCase implements StreamUseCase<MotivoExpiracion, NoParams> {
  const ObservarExpiracionesSesionUseCase(this._repository);

  final AuthRepository _repository;

  @override
  Stream<MotivoExpiracion> call(NoParams params) => _repository.expiraciones;
}

/// Descarta la sesión vencida sin esperar a la red. Los datos locales no se tocan: es un cierre
/// de sesión, no un borrado (HU-AUTH-007).
final class ExpirarSesionUseCase implements UseCase<Unit, MotivoExpiracion> {
  const ExpirarSesionUseCase(this._repository);

  final AuthRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(MotivoExpiracion motivo) => _repository.expirarSesion(motivo);
}
