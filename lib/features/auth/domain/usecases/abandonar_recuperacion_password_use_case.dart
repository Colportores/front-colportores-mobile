import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../repositories/recuperacion_password_repository.dart';

/// HU-AUTH-005 — el usuario salió de la pantalla de la contraseña nueva sin terminar: se suelta la
/// sesión que abrió el enlace. Si no, el próximo arranque la restauraría y quedaría adentro sin
/// haber puesto ninguna contraseña.
final class AbandonarRecuperacionPasswordUseCase implements UseCase<Unit, NoParams> {
  const AbandonarRecuperacionPasswordUseCase(this._repository);

  final RecuperacionPasswordRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) => _repository.abandonar();
}
