import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/cuota.dart';
import '../entities/pedido_de_plan.dart';

/// Persistencia del plan de cuotas de una venta (BACK-HU-COB-004, #399).
///
/// No hay tablas de plan ni de cuotas (decisión «Plan cuotas», 23/10): cada cuota es una cita de
/// cobranza de la agenda con su venta y su monto previsto. Cada escritura es **todo o nada**, en una
/// transacción local: las citas, su encolado para el sync y el recálculo del color de la casa.
abstract interface class PlanDeCuotasRepository {
  /// Agenda una cobranza por cada cuota de [plan] (30A-01 a 30A-04).
  ///
  /// - Con los mismos ids de cita, no escribe nada y devuelve el plan que quedó (idempotente ante un
  ///   doble toque o un reintento).
  /// - Una venta con cuotas por cobrar, sin saldo, o que ya no está, un monto que no entra o más de
  ///   12 cuotas por venta son [FailurePlanDeCuotas]; cualquier otra falla, [FailurePlanNoGuardado]
  ///   (no se agendó ninguna).
  Future<Either<Failure, PlanDeCuotas>> crear(NuevoPlanDeCuotas plan);

  /// Cambia el monto de las cuotas abiertas (30A-09) y las encola; las cubiertas no se tocan. Si un
  /// monto deja una cuota cubierta, pasa a `CUMPLIDA`.
  Future<Either<Failure, PlanDeCuotas>> modificar(ModificacionDeCuotas cambios);

  /// El plan de la venta [ventaId] (sin cuotas si se cobra libre), o `null` si no está en el teléfono.
  Future<Either<Failure, PlanDeCuotas?>> leer(String ventaId);

  /// El plan de la venta [ventaId] cada vez que cambia ella, sus cobros o sus citas. Si la base no se
  /// puede leer, el `Stream` falla con [FailureCuotasNoDisponibles].
  Stream<PlanDeCuotas?> observar(String ventaId);
}
