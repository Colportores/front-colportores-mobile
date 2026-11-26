import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/pedido.dart';

/// Los pedidos a la casa editora de la colportora (HU-STK-009).
abstract interface class PedidoRepository {
  /// Guarda el pedido **por autorizar** con sus líneas y encola su sync, todo o nada. Con el mismo id es
  /// idempotente: devuelve lo que ya estaba sin escribir nada.
  Future<Either<Failure, PedidoEnviado>> enviar(Pedido pedido);

  /// Cancela el pedido [id] si es de [colportorId] y sigue por autorizar. Cancelado ya, devuelve lo mismo.
  Future<Either<Failure, Pedido>> cancelar({
    required String id,
    required String colportorId,
    required DateTime ahora,
  });

  /// Los pedidos de [colportorId], el más nuevo primero, cada vez que cambian. Si no se pueden leer, el
  /// stream falla con [FailurePedidosNoDisponibles].
  Stream<List<Pedido>> observar(String colportorId);
}
