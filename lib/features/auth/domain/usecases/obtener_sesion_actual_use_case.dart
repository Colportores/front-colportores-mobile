import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/motivo_expiracion.dart';
import '../entities/sesion.dart';
import '../repositories/auth_repository.dart';

/// Sesión persistida en el dispositivo, si sigue vigente (HU-AUTH-007).
///
/// Vigente es "dentro de la ventana deslizante de 30 días", no "con el JWT de acceso sin vencer":
/// sin red la app sigue trabajando con la sesión, y el JWT se renueva cuando vuelve la red.
///
/// Si pasaron 30 días sin actividad de red, la sesión se descarta (los datos locales no se
/// tocan) y devuelve `Left(FailureSesionExpiradaPorInactividad)`, para que el login diga por qué.
final class ObtenerSesionActualUseCase implements UseCase<Sesion?, NoParams> {
  const ObtenerSesionActualUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final AuthRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, Sesion?>> call(NoParams params) async {
    final resultado = await _repository.sesionActual();
    final sesion = resultado.getOrElse(() => null);
    if (sesion == null || sesion.estaVigente(ahora: _ahora())) return resultado;

    await _repository.expirarSesion(MotivoExpiracion.inactividad);
    return const Left(FailureSesionExpiradaPorInactividad());
  }
}
