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
}
