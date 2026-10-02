import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/destino_enlace_verificacion_usado.dart';

/// Parámetros de [DecidirDestinoEnlaceVerificacionUsadoUseCase].
final class DecidirDestinoEnlaceParams extends Equatable {
  const DecidirDestinoEnlaceParams({required this.haySesion, this.loginEnSilencio});

  /// Hay una sesión activa en la app.
  final bool haySesion;

  /// Intenta entrar con el email y la contraseña que la pantalla de espera todavía tiene en
  /// memoria (sin guardarlos): devuelve el [Failure] si no entró, o `null` si entró. `null` si la
  /// pantalla de espera no está abierta con esos datos.
  final Future<Failure?> Function()? loginEnSilencio;

  @override
  List<Object?> get props => [haySesion, loginEnSilencio];
}

/// HU-AUTH-002 — «"Vencido" vs "ya usado"»: decide qué mostrar cuando llega un deep link de
/// verificación con `otp_expired` (Supabase no distingue un enlace vencido de uno ya usado).
///
/// 1. Hay sesión activa → [DestinoEnlaceVerificacionUsado.yaVerificado].
/// 2. Hay email y contraseña en memoria → login en silencio: entra → `yaVerificado`; responde
///    `email_not_confirmed` → [DestinoEnlaceVerificacionUsado.expirado]; falla por otra cosa (red,
///    credenciales) → el caso genérico.
/// 3. Nada de eso → [DestinoEnlaceVerificacionUsado.noSabemos] (el caso genérico).
///
/// Nunca devuelve `Left`: todo termina en uno de los tres destinos.
final class DecidirDestinoEnlaceVerificacionUsadoUseCase
    implements UseCase<DestinoEnlaceVerificacionUsado, DecidirDestinoEnlaceParams> {
  const DecidirDestinoEnlaceVerificacionUsadoUseCase();

  @override
  Future<Either<Failure, DestinoEnlaceVerificacionUsado>> call(
    DecidirDestinoEnlaceParams params,
  ) async {
    if (params.haySesion) return const Right(DestinoEnlaceVerificacionUsado.yaVerificado);

    final login = params.loginEnSilencio;
    if (login == null) return const Right(DestinoEnlaceVerificacionUsado.noSabemos);

    final Failure? falla;
    try {
      falla = await login();
    } on Object {
      return const Right(DestinoEnlaceVerificacionUsado.noSabemos);
    }
    return Right(switch (falla) {
      null => DestinoEnlaceVerificacionUsado.yaVerificado,
      FailureEmailNoVerificado() => DestinoEnlaceVerificacionUsado.expirado,
      _ => DestinoEnlaceVerificacionUsado.noSabemos,
    });
  }
}
