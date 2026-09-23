import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../repositories/auth_repository.dart';

/// Parámetros de [SolicitarRecuperacionPasswordUseCase].
final class SolicitarRecuperacionPasswordParams extends Equatable {
  const SolicitarRecuperacionPasswordParams({required this.email});

  final String email;

  @override
  List<Object?> get props => [email];
}

/// HU-AUTH-004 — Solicitud de recuperación de contraseña.
///
/// Valida el email (mismo criterio que el resto de los casos de uso de auth) y delega en el
/// repositorio, que ya enmascara como éxito tanto "el email no existe" como un rate limit del
/// proveedor (anti-enumeración, OWASP) — este caso de uso no agrega ni puede agregar esa
/// distinción.
///
/// Límites de la HU: máximo 1 solicitud por email cada 60 segundos, máximo 5 por hora.
/// - El de 60 segundos es responsabilidad de la UI (cooldown visible en el botón), mismo patrón
///   que el reenvío de verificación de email (HU-AUTH-002, issue #19).
/// - El de 5 por hora **no está resuelto**: el `config.toml` de `backend-supabase` solo trae
///   `auth.rate_limit.email_sent = 2` por hora, compartido entre *todos* los emails de Auth
///   (confirmación + reset), no 5 por hora y por email como pide la HU. Si hace falta un límite
///   más fino, dónde se aplica (cliente, Edge Function, cambiar la config de Supabase) es una
///   decisión pendiente de Cristian — no se inventa acá (ver comentario en el issue #46).
final class SolicitarRecuperacionPasswordUseCase
    implements UseCase<Unit, SolicitarRecuperacionPasswordParams> {
  const SolicitarRecuperacionPasswordUseCase(this._repository);

  final AuthRepository _repository;

  static final RegExp _emailRegExp = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  @override
  Future<Either<Failure, Unit>> call(SolicitarRecuperacionPasswordParams params) async {
    final email = params.email.trim().toLowerCase();

    if (email.isEmpty) {
      return const Left(FailureValidacion(campos: {'email': 'Ingresá tu email'}));
    }
    if (!_emailRegExp.hasMatch(email)) {
      return const Left(FailureValidacion(campos: {'email': 'El email no es válido'}));
    }

    return _repository.solicitarRecuperacionPassword(email: email);
  }
}
