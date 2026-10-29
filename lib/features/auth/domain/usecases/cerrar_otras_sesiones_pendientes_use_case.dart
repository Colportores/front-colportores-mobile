import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../repositories/recuperacion_password_repository.dart';

/// HU-AUTH-005, seguimiento de #542: si al cambiar la contraseña no se pudieron cerrar las sesiones
/// de los otros teléfonos, el login siguiente lo reintenta (scope `others`: la sesión nueva queda).
/// Best-effort: sin red o con error sigue pendiente y no molesta a la persona.
final class CerrarOtrasSesionesPendientesUseCase implements UseCase<Unit, NoParams> {
  const CerrarOtrasSesionesPendientesUseCase(this._repository);

  final RecuperacionPasswordRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) =>
      _repository.cerrarOtrasSesionesPendientes();
}
