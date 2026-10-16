import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/espacio.dart';
import '../repositories/espacio_repository.dart';

/// Parámetros de [ListarEspaciosUseCase].
final class ListarEspaciosParams extends Equatable {
  const ListarEspaciosParams({required this.ubicacionId, this.incluirBajas = false});

  final String ubicacionId;

  /// Incluye los espacios dados de baja (para restaurarlos).
  final bool incluirBajas;

  @override
  List<Object?> get props => [ubicacionId, incluirBajas];
}

/// HU-UBI-007 — Listar los espacios de una ubicación, por `numero_depto`.
///
/// Sin `ubicacionId`: `Left(FailureValidacion)`. En una `CASA` la lista trae solo el espacio
/// default; la pantalla no muestra la sección "Espacios" (escenario "CASA — espacios ocultos").
final class ListarEspaciosUseCase implements UseCase<List<Espacio>, ListarEspaciosParams> {
  ListarEspaciosUseCase(this._repository);

  final EspacioRepository _repository;

  @override
  Future<Either<Failure, List<Espacio>>> call(ListarEspaciosParams params) {
    final ubicacionId = params.ubicacionId.trim();
    if (ubicacionId.isEmpty) {
      return Future.value(
        const Left(FailureValidacion(campos: {'ubicacionId': 'Falta la ubicación'})),
      );
    }
    return _repository.listar(ubicacionId, incluirBajas: params.incluirBajas);
  }
}
