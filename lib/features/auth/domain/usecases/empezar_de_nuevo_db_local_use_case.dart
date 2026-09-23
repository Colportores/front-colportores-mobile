import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../repositories/db_local_repository.dart';

/// "Empezar de nuevo" de ADR-006: el almacén seguro falló con la DB en el teléfono y no hay
/// envoltorio por contraseña con qué recuperarla ([FailureAlmacenSeguroSinRecuperacion]).
///
/// **Destructivo y solo con el sí explícito del usuario.** La UI avisa antes que se pierden las
/// personas y las notas guardadas en el teléfono y que lo sincronizado se vuelve a bajar; recién
/// con ese sí llama a este caso de uso. Nunca se llama solo.
///
/// Deja el dispositivo sin DB, sin DEK y sin envoltorio. Después la UI vuelve a llamar a
/// `InicializarDbLocalUseCase`, que lo trata como dispositivo nuevo.
final class EmpezarDeNuevoDbLocalUseCase implements UseCase<Unit, NoParams> {
  const EmpezarDeNuevoDbLocalUseCase(this._repository);

  final DbLocalRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) => _repository.descartar();
}
