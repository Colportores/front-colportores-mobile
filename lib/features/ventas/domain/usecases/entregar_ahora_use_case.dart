import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/entrega.dart';
import '../repositories/entrega_repository.dart';

/// Parámetros de [EntregarAhoraUseCase].
final class EntregarAhoraParams extends Equatable {
  const EntregarAhoraParams({required this.ventaId, required this.colportorId});

  final String ventaId;

  /// Quién entrega: el `created_by` de las filas.
  final String colportorId;

  @override
  List<Object?> get props => [ventaId, colportorId];
}

/// HU-VEN-002: «Entregar ahora». Marca como entregado todo lo vendido en la venta —una fila por
/// producto, un combo en una fila por componente— y deja la casa del color que corresponde, todo en
/// una sola transacción.
///
/// 1. No guarda nada si faltan los ids.
/// 2. Pone la hora de ahora como fecha de la entrega.
/// 3. Lo guarda por [EntregaRepository.entregarAhora], que es idempotente: un doble toque o un
///    reintento tras una falla no entrega dos veces.
///
/// En V1 no hay stock: la app confía en lo que lleva la colportora (decisión del 23/10, el stock es
/// V2, HU-STK-007).
final class EntregarAhoraUseCase implements UseCase<EntregaRegistrada, EntregarAhoraParams> {
  EntregarAhoraUseCase(this._repository, {required this._generarId, DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final EntregaRepository _repository;
  final String Function() _generarId;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, EntregaRegistrada>> call(EntregarAhoraParams params) async {
    if (params.ventaId.trim().isEmpty || params.colportorId.trim().isEmpty) {
      return const Left(FailureEntregaNoGuardada(causa: 'faltan_ids'));
    }
    return _repository.entregarAhora(
      params.ventaId.trim(),
      colportorId: params.colportorId.trim(),
      ahora: _ahora().toUtc(),
      generarId: _generarId,
    );
  }
}
