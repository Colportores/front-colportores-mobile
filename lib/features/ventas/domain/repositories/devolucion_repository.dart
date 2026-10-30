import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/devolucion.dart';
import '../entities/venta_para_devolver.dart';

/// Persistencia de las devoluciones de una venta (HU-VEN-004, ADR-002).
///
/// Registrar es **todo o nada**, en una transacción local: la fila de `devolucion`, su encolado para el
/// sync (sin dato del cliente) y el recálculo del color de la casa (`house_status`, R-UB08).
abstract interface class DevolucionRepository {
  /// La venta [ventaId] con lo vendido, lo pagado y lo que ya volvió, o `null` si no está en el
  /// teléfono o se dio de baja. Solo lee. Si no se puede leer es [FailureDevolucionNoDisponible]: no es
  /// lo mismo que «no está».
  Future<Either<Failure, VentaParaDevolver?>> ventaParaDevolver(String ventaId);

  /// Registra la devolución de [pedido].
  ///
  /// Dentro de la misma transacción comprueba, con lo que hay en el teléfono en ese momento:
  /// 1. la venta existe ([FailureDevolucionSinVenta]);
  /// 2. no pasaron 72 h desde la venta ([FailureDevolucionFueraDePlazo]);
  /// 3. hay algo elegido y nada pasa de lo que queda por devolver, y si el cliente pagó de más hay una
  ///    elección ([FailureDevolucionInvalida]).
  ///
  /// Es idempotente por `pedido.id`: un doble toque o un reintento con el mismo id no escribe nada y
  /// devuelve lo mismo ([DevolucionRegistrada.yaEstaba]). Cualquier otra falla es
  /// [FailureDevolucionNoGuardada]: no se guarda nada.
  Future<Either<Failure, DevolucionRegistrada>> registrar(PedidoDeDevolucion pedido);
}
