import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/entrega.dart';

/// Persistencia de las entregas de lo vendido (BACK-HU-VEN-002, #430).
///
/// Cada operación que escribe es **todo o nada**, en una transacción local: las filas de `entrega`,
/// su encolado para el sync (sin dato del cliente) y el recálculo del color de la casa
/// (`house_status`, R-UB08).
abstract interface class EntregaRepository {
  /// Guarda las [filas] de la entrega inmediata de la venta [ventaId]: las entregadas y las que la
  /// colportora dejó para otro día.
  ///
  /// - Si la venta ya tiene filas de entrega, no escribe nada y devuelve las que había
  ///   ([EntregaRegistrada.yaEstaba]): un doble toque o un reintento no entrega dos veces.
  /// - Una venta que no está en el teléfono, o cualquier otra falla, es [FailureEntregaNoGuardada]:
  ///   no se guarda nada.
  Future<Either<Failure, EntregaRegistrada>> entregarAhora(String ventaId, List<Entrega> filas);

  /// Las filas vivas de la venta [ventaId] (vacío si todavía no se entregó nada). Solo lee.
  Future<Either<Failure, List<Entrega>>> deLaVenta(String ventaId);
}
