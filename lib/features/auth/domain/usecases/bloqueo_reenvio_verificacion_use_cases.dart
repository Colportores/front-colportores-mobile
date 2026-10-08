import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../repositories/bloqueo_reenvio_verificacion_repository.dart';

/// Cuánto queda bloqueado el reenvío del email de verificación a una dirección cuando Supabase lo
/// rechaza por límite (decisión de Cristian, 29/09, #221): una hora fija desde el rechazo, porque
/// Supabase no informa cuánto falta.
const Duration bloqueoReenvioVerificacion = Duration(minutes: 60);

/// La dirección tal como se la compara para el candado: sin espacios alrededor y en minúsculas
/// (Supabase guarda los correos en minúsculas, así que `Lucia@Correo.com` y `lucia@correo.com` son
/// la misma dirección).
String correoParaBloqueo(String correo) => correo.trim().toLowerCase();

/// Parámetros de [ConsultarBloqueosReenvioVerificacionUseCase].
final class ConsultarBloqueosReenvioVerificacionParams extends Equatable {
  const ConsultarBloqueosReenvioVerificacionParams({required this.ahora});

  /// La hora de ahora, según el reloj de quien pregunta.
  final DateTime ahora;

  @override
  List<Object?> get props => [ahora];
}

/// Los candados del reenvío de verificación que siguen vigentes (HU-AUTH-002, vista 12-A06):
/// correo normalizado ([correoParaBloqueo]) → instante en que vence. Los vencidos no vuelven.
///
/// **Un candado nunca dura más de una hora ([bloqueoReenvioVerificacion])**, aunque cambie la hora
/// del teléfono: si el vencimiento guardado queda a más de una hora (el reloj se atrasó, o estaba
/// adelantado cuando se guardó), se cuenta una hora desde ahora, no más. Es la misma regla que ya
/// tiene la espera del enlace de recuperación (decisión del orquestador, 05/10, #275 y #281).
///
/// Nunca falla: si el teléfono no puede decir qué correos están bloqueados, no hay candados (el
/// límite de verdad lo aplica el servidor).
final class ConsultarBloqueosReenvioVerificacionUseCase
    implements UseCase<Map<String, DateTime>, ConsultarBloqueosReenvioVerificacionParams> {
  const ConsultarBloqueosReenvioVerificacionUseCase(this._repository);

  final BloqueoReenvioVerificacionRepository _repository;

  @override
  Future<Either<Failure, Map<String, DateTime>>> call(
    ConsultarBloqueosReenvioVerificacionParams params,
  ) async {
    final guardados = await _repository.leer();
    final tope = params.ahora.add(bloqueoReenvioVerificacion);
    final vigentes = <String, DateTime>{};
    for (final MapEntry(key: correo, value: vence) in guardados.entries) {
      if (!vence.isAfter(params.ahora)) continue;
      vigentes[correo] = vence.isAfter(tope) ? tope : vence;
    }
    return Right(vigentes);
  }
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
