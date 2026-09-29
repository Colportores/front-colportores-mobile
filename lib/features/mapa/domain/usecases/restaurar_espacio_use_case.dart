import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/espacio.dart';
import '../repositories/espacio_repository.dart';

/// Parámetros de [RestaurarEspacioUseCase].
final class RestaurarEspacioParams extends Equatable {
  const RestaurarEspacioParams({required this.id});

  final String id;

  @override
  List<Object?> get props => [id];
}

/// HU-UBI-007 — Restaurar un espacio dado de baja (simétrico a HU-UBI-005).
///
/// Sin `id`: `Left(FailureValidacion)`. El repositorio valida en la transacción que el espacio
/// exista, que su ubicación esté activa y que su número no repita el de otro espacio activo (lo
/// pudo tomar otro mientras estaba de baja). Ya activo: lo devuelve sin escribir.
final class RestaurarEspacioUseCase implements UseCase<Espacio, RestaurarEspacioParams> {
  RestaurarEspacioUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final EspacioRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, Espacio>> call(RestaurarEspacioParams params) {
    final id = params.id.trim();
    if (id.isEmpty) {
      return Future.value(
        const Left(FailureValidacion(campos: {'id': 'Falta el espacio a restaurar'})),
      );
    }
    return _repository.restaurar(id, ahora: _ahora());
  }
}
