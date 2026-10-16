import '../../../../core/usecases/use_case.dart';
import '../repositories/auth_repository.dart';

/// HU-AUTH-002 — Verificación de email exitosa por enlace (issue #84).
///
/// Sin validación ni transformación propia: es un paso al costado del repositorio, igual que
/// [StreamUseCase] lo describe ("p. ej. un `watch` de Drift"). Simétrico a
/// `ObservarErroresVerificacionUseCase`: la raíz de la app se suscribe una sola vez, por el
/// tiempo que vive la app, para llevar a la pantalla de verificación en estado "verificado" aunque
/// el usuario no esté navegando dentro de la app en ese momento (o la app arrancó en frío desde el
/// enlace).
final class ObservarVerificacionesExitosasUseCase implements StreamUseCase<void, NoParams> {
  const ObservarVerificacionesExitosasUseCase(this._repository);

  final AuthRepository _repository;

  @override
  Stream<void> call(NoParams params) => _repository.verificacionesExitosas;
}
