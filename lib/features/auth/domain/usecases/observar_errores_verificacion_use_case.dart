import '../../../../core/usecases/use_case.dart';
import '../repositories/auth_repository.dart';

/// HU-AUTH-002 — Errores del deep link de verificación de email (enlace vencido o ya usado).
///
/// Sin validación ni transformación propia: es un paso al costado del repositorio, igual que
/// [StreamUseCase] lo describe ("p. ej. un `watch` de Drift"). La raíz de la app se suscribe una
/// sola vez, por el tiempo que vive la app, para llevar a la pantalla de verificación en estado
/// "expirado" aunque el usuario no esté navegando dentro de la app en ese momento.
final class ObservarErroresVerificacionUseCase implements StreamUseCase<void, NoParams> {
  const ObservarErroresVerificacionUseCase(this._repository);

  final AuthRepository _repository;

  @override
  Stream<void> call(NoParams params) => _repository.erroresVerificacionEmail;
}
