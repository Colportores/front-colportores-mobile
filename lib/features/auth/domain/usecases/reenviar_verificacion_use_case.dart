import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../repositories/auth_repository.dart';

/// Parámetros de [ReenviarVerificacionUseCase].
final class ReenviarVerificacionParams extends Equatable {
  const ReenviarVerificacionParams({required this.email});

  final String email;

  @override
  List<Object?> get props => [email];
}

/// HU-AUTH-002 — Reenvío manual del email de verificación.
///
/// Valida el email (mismo criterio que [IniciarSesionUseCase]) y delega en el repositorio. El
/// límite de "máximo 1 reenvío cada 60 segundos" es responsabilidad de la UI (cooldown visible en
/// el botón); el de "máximo 5 por hora" no se replica acá: Supabase ya lo hace cumplir del lado
/// del servidor (~2 emails/hora en el plan free sin SMTP propio) y ese rechazo llega traducido
/// como cualquier otro [FailureServidor] de rate limit.
final class ReenviarVerificacionUseCase implements UseCase<Unit, ReenviarVerificacionParams> {
  const ReenviarVerificacionUseCase(this._repository);

  final AuthRepository _repository;

  static final RegExp _emailRegExp = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  @override
  Future<Either<Failure, Unit>> call(ReenviarVerificacionParams params) async {
    final email = params.email.trim().toLowerCase();

    if (email.isEmpty) {
      return const Left(FailureValidacion(campos: {'email': 'Ingresá tu email'}));
    }
    if (!_emailRegExp.hasMatch(email)) {
      return const Left(FailureValidacion(campos: {'email': 'El email no es válido'}));
    }

    return _repository.reenviarVerificacion(email: email);
  }
}
