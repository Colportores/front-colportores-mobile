import '../../../../core/usecases/use_case.dart';
import '../entities/enlace_recuperacion.dart';
import '../repositories/recuperacion_password_repository.dart';

/// HU-AUTH-005 — los enlaces de recuperación que llegan a la app, para que la raíz lleve a la
/// pantalla de la contraseña nueva (o a la de enlace vencido).
final class ObservarEnlacesRecuperacionUseCase
    implements StreamUseCase<EnlaceRecuperacion, NoParams> {
  const ObservarEnlacesRecuperacionUseCase(this._repository);

  final RecuperacionPasswordRepository _repository;

  @override
  Stream<EnlaceRecuperacion> call(NoParams params) => _repository.enlaces;
}
