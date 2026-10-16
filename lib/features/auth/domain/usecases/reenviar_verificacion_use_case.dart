import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../repositories/auth_repository.dart';
import '../services/validador_email.dart';

/// Parámetros de [ReenviarVerificacionUseCase].
final class ReenviarVerificacionParams extends Equatable {
  const ReenviarVerificacionParams({required this.email});

  final String email;

  @override
  List<Object?> get props => [email];
}

/// HU-AUTH-002 — Reenvío manual del email de verificación.
///
/// Valida el email (con [ValidadorEmail], el mismo criterio que el resto de los casos de uso de
/// auth) y delega en el repositorio. El límite de "máximo 1 reenvío cada 60 segundos" es
/// responsabilidad de la UI (cooldown visible en el botón); el de "máximo 5 por hora" no se replica
/// acá: Supabase ya lo hace cumplir del lado del servidor (~2 emails/hora en el plan free sin SMTP
/// propio) y ese rechazo llega traducido como cualquier otro [FailureServidor] de rate limit.
final class ReenviarVerificacionUseCase implements UseCase<Unit, ReenviarVerificacionParams> {
  const ReenviarVerificacionUseCase(this._repository);

  final AuthRepository _repository;

  /// Lo que dice el campo cuando el email está incompleto o mal armado.
  static const String _emailIncompleto = 'El email no es válido';

  @override
  Future<Either<Failure, Unit>> call(ReenviarVerificacionParams params) async {
    final email = ValidadorEmail.normalizar(params.email);

    if (email.isEmpty) {
      return const Left(FailureValidacion(campos: {'email': 'Ingresá tu email'}));
    }
    if (ValidadorEmail.mensaje(email, siIncompleto: _emailIncompleto) case final aviso?) {
      return Left(FailureValidacion(campos: {'email': aviso}));
    }

    return _repository.reenviarVerificacion(email: email);
  }
}
