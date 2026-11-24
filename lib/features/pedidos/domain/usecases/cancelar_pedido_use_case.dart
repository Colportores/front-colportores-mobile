import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/usecases/use_case.dart';
import '../entities/pedido.dart';
import '../repositories/pedido_repository.dart';

/// Parámetros de [CancelarPedidoUseCase].
final class CancelarPedidoParams extends Equatable {
  const CancelarPedidoParams({required this.pedidoId, required this.colportorId});

  final String pedidoId;
  final String colportorId;

  @override
  List<Object?> get props => [pedidoId, colportorId];
}

/// HU-STK-009: la colportora cancela su pedido mientras está por autorizar. Desde el teléfono es lo único
/// que puede cambiar de un pedido, y el pedido no se borra: queda `CANCELADO`. La cancelación no vuelve
/// atrás (decisión de Cristian, 27/10, «Cancelar ped»). Cancelar un pedido ya cancelado responde lo mismo.
final class CancelarPedidoUseCase implements UseCase<Pedido, CancelarPedidoParams> {
  CancelarPedidoUseCase(this._repository, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final PedidoRepository _repository;
  final DateTime Function() _ahora;

  @override
  Future<Either<Failure, Pedido>> call(CancelarPedidoParams params) {
    if (params.pedidoId.trim().isEmpty || params.colportorId.trim().isEmpty) {
      return Future.value(const Left(FailurePedidoNoCancelable()));
    }
    return _repository.cancelar(
      id: params.pedidoId.trim(),
      colportorId: params.colportorId.trim(),
      ahora: _ahora().toUtc(),
    );
  }
}
