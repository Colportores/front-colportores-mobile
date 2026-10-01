import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/estado_cuenta.dart';

/// Estado de la cuenta del colportor (HU-AUTH-008).
abstract interface class CuentaRepository {
  /// Consulta el estado en el backend y lo recuerda en el equipo para [usuarioId].
  /// `Left(FailureSinConexion)` sin red; `Left(FailureServidor)` si el backend falla.
  Future<Either<Failure, EstadoCuenta>> consultar(String usuarioId);

  /// El último estado que informó el backend para [usuarioId] en este equipo, o `null`.
  Future<EstadoCuenta?> ultimoConocido(String usuarioId);

  /// Cuándo se consultó el estado al backend con éxito por última vez en esta ejecución de la app
  /// para [usuarioId], o `null` si todavía no (el último estado conocido pudo venir del equipo).
  /// Sirve para decirle al colportor cuándo fue la última revisión (vista 18).
  DateTime? ultimaConsultaExitosa(String usuarioId);
}
