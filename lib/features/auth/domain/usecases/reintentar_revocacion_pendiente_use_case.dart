import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../repositories/auth_repository.dart';

/// HU-AUTH-006, escenario "Logout sin conexión": reintenta la revocación del JWT que quedó
/// pendiente. Best-effort — sin red sigue pendiente y no molesta al usuario (no puede hacer nada).
final class ReintentarRevocacionPendienteUseCase implements UseCase<Unit, NoParams> {
  const ReintentarRevocacionPendienteUseCase(this._repository);

  final AuthRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) =>
      _repository.reintentarRevocacionPendiente();
}
