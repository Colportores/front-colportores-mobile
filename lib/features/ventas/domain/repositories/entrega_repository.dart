import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/entrega.dart';

/// Persistencia de las entregas de lo vendido (BACK-HU-VEN-002, #430).
///
/// Cada operación que escribe es **todo o nada**, en una transacción local: las filas de `entrega`,
/// su encolado para el sync (sin dato del cliente) y el recálculo del color de la casa
/// (`house_status`, R-UB08).
abstract interface class EntregaRepository {
  /// Entrega **ahora** todo lo vendido en [ventaId]: una fila por producto con lo que falta entregar
  /// (un combo, una por componente), ya entregada, con [ahora] como fecha de entrega y [colportorId]
  /// como autor. [generarId] da el id de cada fila nueva.
  ///
  /// - Es idempotente: si la venta ya está toda entregada, no escribe nada y devuelve lo que había
  ///   ([EntregaRegistrada.yaEstaba]); un doble toque o un reintento no entrega dos veces.
  /// - Una venta que no está en el teléfono, o cualquier otra falla, es [FailureEntregaNoGuardada]:
  ///   no se guarda nada.
  Future<Either<Failure, EntregaRegistrada>> entregarAhora(
    String ventaId, {
    required String colportorId,
    required DateTime ahora,
    required String Function() generarId,
  });

  /// Las filas vivas de la venta [ventaId] (vacío si todavía no se entregó nada). Solo lee. Si no se
  /// puede leer es [FailureEntregaNoDisponible]: no es lo mismo que «nada entregado».
  Future<Either<Failure, List<Entrega>>> deLaVenta(String ventaId);
}
