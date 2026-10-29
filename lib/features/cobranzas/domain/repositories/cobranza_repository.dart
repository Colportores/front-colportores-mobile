import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/cobranza.dart';
import '../entities/venta_con_saldo.dart';

/// Persistencia de los cobros del colportor (BACK-HU-COB-001, #436).
///
/// Cada escritura es **todo o nada**, en una transacción local: el cobro, su encolado para el sync
/// (sin dato del cliente, R-CB03) y el recálculo del color de la casa (`house_status`, R-UB08).
abstract interface class CobranzaRepository {
  /// Guarda [cobro] en efectivo.
  ///
  /// - Si ya hay un cobro con ese `id`, no escribe nada y devuelve el que estaba (idempotente ante un
  ///   doble toque o un reintento).
  /// - Un monto mayor al saldo de la venta es [FailureCobroMayorAlSaldo]; una venta que ya no está en
  ///   el teléfono, [FailureCobroSinVenta]; cualquier otra falla, [FailureCobroNoGuardado].
  Future<Either<Failure, CobroRegistrado>> registrar(Cobranza cobro);

  /// La venta [ventaId] con su saldo, o `null` si no está (o está dada de baja).
  Future<Either<Failure, VentaConSaldo?>> ventaConSaldo(String ventaId);

  /// Las ventas vivas con saldo mayor a cero de la persona [personaId], la más vieja primero.
  Future<Either<Failure, List<VentaConSaldo>>> ventasConSaldoDe(String personaId);
}
