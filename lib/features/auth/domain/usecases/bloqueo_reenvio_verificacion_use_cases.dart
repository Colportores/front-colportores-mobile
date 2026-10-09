import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/reenvios_guardados.dart';
import '../repositories/bloqueo_reenvio_verificacion_repository.dart';

/// La dirección tal como se la compara para el candado y para la espera: sin espacios alrededor y en
/// minúsculas (Supabase guarda los correos en minúsculas, así que `Lucia@Correo.com` y
/// `lucia@correo.com` son la misma dirección).
String correoParaBloqueo(String correo) => correo.trim().toLowerCase();

/// Parámetros de [ConsultarReenviosVerificacionUseCase].
final class ConsultarReenviosVerificacionParams extends Equatable {
  const ConsultarReenviosVerificacionParams({required this.ahora});

  /// La hora de ahora, según el reloj de quien pregunta.
  final DateTime ahora;

  @override
  List<Object?> get props => [ahora];
}

/// Los candados y las esperas del reenvío de verificación que siguen vigentes (HU-AUTH-002, vista
/// 12-A06): por correo normalizado ([correoParaBloqueo]), con el instante en que vencen. Los
/// vencidos no vuelven y se borran del teléfono.
///
/// **Un candado nunca dura más de una hora ([bloqueoReenvioVerificacion]) ni una espera más de 60 s
/// ([esperaReenvioVerificacion])**, aunque cambie la hora del teléfono: si el vencimiento guardado
/// queda más lejos que su tope (el reloj se atrasó, o estaba adelantado cuando se guardó), se
/// cuenta el tope desde ahora, no más, y queda guardado así (ver
/// [BloqueoReenvioVerificacionRepository.leer]). Es la misma regla que ya tiene la espera del
/// enlace de recuperación (decisión del orquestador, 05/10, #275 y #281).
///
/// Nunca falla: si el teléfono no puede decir qué correos están bloqueados, no hay candados (el
/// límite de verdad lo aplica el servidor).
final class ConsultarReenviosVerificacionUseCase
    implements UseCase<ReenviosGuardados, ConsultarReenviosVerificacionParams> {
  const ConsultarReenviosVerificacionUseCase(this._repository);

  final BloqueoReenvioVerificacionRepository _repository;

  @override
  Future<Either<Failure, ReenviosGuardados>> call(
    ConsultarReenviosVerificacionParams params,
  ) async => Right(await _repository.leer(ahora: params.ahora));
}

/// Parámetros de [RegistrarBloqueoReenvioVerificacionUseCase].
final class RegistrarBloqueoReenvioVerificacionParams extends Equatable {
  const RegistrarBloqueoReenvioVerificacionParams({required this.correo, required this.ahora});

  /// La dirección a la que el servidor rechazó el reenvío, tal como se la pidió (el caso de uso la
  /// normaliza).
  final String correo;

  /// Cuándo rechazó el servidor, según el reloj de quien lo pidió.
  final DateTime ahora;

  @override
  List<Object?> get props => [correo, ahora];

  /// El correo no se imprime nunca, ni con `EquatableConfig.stringify` en `true` (mismo criterio
  /// que `IniciarSesionParams`).
  @override
  bool? get stringify => false;
}

/// Guarda en el teléfono que el reenvío del email de verificación a [correo] queda bloqueado una
/// hora desde el rechazo por límite ([bloqueoReenvioVerificacion]), para que el candado sobreviva
/// a salir de la pantalla y a reiniciar la app (decisión de Cristian, 30/09, #221, #239 y #249).
/// Devuelve el instante en que vence.
///
/// Un correo en blanco no se guarda: no hay dirección a la que bloquear.
final class RegistrarBloqueoReenvioVerificacionUseCase
    implements UseCase<DateTime, RegistrarBloqueoReenvioVerificacionParams> {
  const RegistrarBloqueoReenvioVerificacionUseCase(this._repository);

  final BloqueoReenvioVerificacionRepository _repository;

  @override
  Future<Either<Failure, DateTime>> call(RegistrarBloqueoReenvioVerificacionParams params) async {
    final vence = params.ahora.add(bloqueoReenvioVerificacion);
    final correo = correoParaBloqueo(params.correo);
    if (correo.isNotEmpty) await _repository.guardar(correo, vence, ahora: params.ahora);
    return Right(vence);
  }
}

/// Parámetros de [RegistrarEnvioVerificacionUseCase].
final class RegistrarEnvioVerificacionParams extends Equatable {
  const RegistrarEnvioVerificacionParams({required this.correo, required this.ahora});

  /// La dirección a la que salió el correo, tal como se la pidió (el caso de uso la normaliza).
  final String correo;

  /// Cuándo salió, según el reloj de quien lo pidió.
  final DateTime ahora;

  @override
  List<Object?> get props => [correo, ahora];

  /// El correo no se imprime nunca (ver [RegistrarBloqueoReenvioVerificacionParams]).
  @override
  bool? get stringify => false;
}

/// Guarda en el teléfono cuándo salió el último correo de verificación a [RegistrarEnvioVerificacionParams.correo]
/// —el del alta o un reenvío—, para que la espera de 60 s ([esperaReenvioVerificacion]) cuente
/// desde ahí aunque la persona salga de la pantalla y vuelva, o reinicie la app (HU-AUTH-002:
/// «máximo 1 reenvío cada 60 segundos»; decisión del orquestador, 08/10, #325). Devuelve el
/// instante en que vence la espera.
///
/// Un correo en blanco no se guarda. Un rechazo por límite no pasa por acá: eso es un candado de
/// una hora ([RegistrarBloqueoReenvioVerificacionUseCase]).
final class RegistrarEnvioVerificacionUseCase
    implements UseCase<DateTime, RegistrarEnvioVerificacionParams> {
  const RegistrarEnvioVerificacionUseCase(this._repository);

  final BloqueoReenvioVerificacionRepository _repository;

  @override
  Future<Either<Failure, DateTime>> call(RegistrarEnvioVerificacionParams params) async {
    final vence = params.ahora.add(esperaReenvioVerificacion);
    final correo = correoParaBloqueo(params.correo);
    if (correo.isNotEmpty) await _repository.guardarEspera(correo, vence, ahora: params.ahora);
    return Right(vence);
  }
}
