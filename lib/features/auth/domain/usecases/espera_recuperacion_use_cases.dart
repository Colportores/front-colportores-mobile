import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../repositories/ultimo_envio_recuperacion_repository.dart';

/// Parámetros de [ConsultarEsperaRecuperacionUseCase].
final class ConsultarEsperaRecuperacionParams extends Equatable {
  const ConsultarEsperaRecuperacionParams({required this.ahora});

  /// La hora de ahora, según el reloj de quien pregunta.
  final DateTime ahora;

  @override
  List<Object?> get props => [ahora];
}

/// Cuánto falta para poder pedir otro enlace de recuperación (HU-AUTH-004, vista 14): la espera de
/// 60 s contada desde la hora del último envío que guarda el teléfono (decisión de Cristian,
/// 02/10, #223; seguimiento #281). `Duration.zero` si no hay espera.
///
/// **La espera nunca pasa de 60 s**, aunque cambie la hora del teléfono: si la hora guardada queda
/// en el futuro (se atrasó el reloj), se cuenta como recién enviada, no más (decisión del
/// orquestador, 05/10, por el mapa de decisiones, #275). Y **se corrige sola** (agente de
/// decisiones, 10/10, #318): la hora de ahora reemplaza a la guardada, así la espera baja entre
/// entradas en vez de mostrar 60 s completos cada vez hasta que el reloj alcance la hora vieja.
///
/// Nunca falla: si el teléfono no puede decir cuándo fue el último envío, no hay espera (el límite
/// de verdad lo aplica el servidor).
final class ConsultarEsperaRecuperacionUseCase
    implements UseCase<Duration, ConsultarEsperaRecuperacionParams> {
  const ConsultarEsperaRecuperacionUseCase(this._repository);

  /// HU-AUTH-004: «máximo 1 solicitud por email cada 60 segundos».
  static const Duration espera = Duration(seconds: 60);

  final UltimoEnvioRecuperacionRepository _repository;

  @override
  Future<Either<Failure, Duration>> call(ConsultarEsperaRecuperacionParams params) async {
    final ultimo = await _repository.leer();
    if (ultimo == null) return const Right(Duration.zero);
    final transcurrido = params.ahora.difference(ultimo);
    if (transcurrido.isNegative) {
      // Hora guardada en el futuro: se cuenta como recién enviada, no más, y se guarda la de ahora
      // para que la espera corra desde acá. No se espera el guardado (el repositorio ejecuta en
      // orden: cualquier lectura o guardado que venga detrás lo ve), así un almacén lento no demora
      // la respuesta; y si el guardado falla, no pasa nada: la espera sigue siendo de 60 s.
      unawaited(_repository.guardar(params.ahora).catchError((Object _) {}));
      return const Right(espera);
    }
    final restante = espera - transcurrido;
    return Right(restante.isNegative ? Duration.zero : restante);
  }
}

/// Parámetros de [RegistrarEnvioRecuperacionUseCase].
final class RegistrarEnvioRecuperacionParams extends Equatable {
  const RegistrarEnvioRecuperacionParams({required this.cuando});

  /// Cuándo salió el enlace, según el reloj de quien lo pidió.
  final DateTime cuando;

  @override
  List<Object?> get props => [cuando];
}

/// Guarda en el teléfono la hora del último enlace de recuperación pedido, para que la espera de
/// 60 s no se reinicie al salir de «Olvidé mi contraseña» y volver a entrar (decisión de Cristian,
/// 02/10, #223). Por teléfono, no por correo.
final class RegistrarEnvioRecuperacionUseCase
    implements UseCase<Unit, RegistrarEnvioRecuperacionParams> {
  const RegistrarEnvioRecuperacionUseCase(this._repository);

  final UltimoEnvioRecuperacionRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(RegistrarEnvioRecuperacionParams params) async {
    await _repository.guardar(params.cuando);
    return const Right(unit);
  }
}
