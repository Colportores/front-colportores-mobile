import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/nueva_venta.dart';
import '../entities/venta_abierta.dart';
import '../entities/venta_item.dart';

/// «Venta crece» (HU-VEN-001, decisión de Cristian del 10/11): las ventas abiertas de una persona y
/// sumarle renglones a una de ellas, sin otro talonario.
///
/// Es un puerto aparte de `VentaRepository` a propósito: lo que lee y escribe es de otra pantalla
/// (42B·09), y así los dobles de la venta de siempre no cambian.
/// Las citas `PROGRAMADA` que ya tiene una venta: deciden qué ofrece 42B·09D después de sumar. Una
/// cobranza agendada de esa persona (con la venta o sin venta) hace que no se vuelva a preguntar
/// «¿Cuándo volvés a cobrar?». Una entrega agendada de la venta no cuenta: el libro nuevo tiene su
/// propia cita (decisión de Cristian del 11/11, «Entrega cita»).
typedef CitasDeLaVenta = ({bool cobranzaAgendada});

abstract interface class VentaQueCreceRepository {
  /// Las citas que ya tiene la venta [ventaId] (ver [CitasDeLaVenta]). Solo lee.
  Future<Either<Failure, CitasDeLaVenta>> citasDe(String ventaId);

  /// Las ventas abiertas de la persona [personaId] (de todos sus vínculos vivos), de la más reciente a
  /// la más vieja, cada vez que cambia una venta, sus renglones, sus cobros, sus entregas o sus
  /// devoluciones. Si la base no se puede leer, el `Stream` falla.
  Stream<List<VentaAbierta>> observarAbiertasDe(String personaId);

  /// Suma [itemsNuevos] a la venta [ventaId] en **una transacción**: la venta con el total nuevo (el
  /// que tenía más [sumadoCentavos]) y la cantidad nueva de renglones (`items_esperados`), y después
  /// los renglones nuevos, en ese orden también en la cola del sync (el servidor valida el total con
  /// la regla de «Total arriba»); la diferencia del monto a mano en el `audit_log` local
  /// ([diferenciaCentavos], sin el motivo) y el color de la casa. Nada de lo que la venta ya tenía se
  /// borra ni se renombra. Con [motivoMontoManual] la venta guarda ese motivo; sin él, conserva el suyo.
  ///
  /// - Si el primer renglón nuevo ya está guardado, no escribe nada y devuelve cómo quedó
  ///   ([VentaQueCrecio.yaEstaba]): un doble toque o un reintento no suma dos veces.
  /// - Una venta que ya no está abierta (se pagó y entregó, se anuló o se devolvió todo) o que ya no
  ///   está en el teléfono es [FailureVentaCerrada]; cualquier otra falla, [FailureVentaNoGuardada].
  Future<Either<Failure, VentaQueCrecio>> sumar(
    String ventaId,
    List<VentaItem> itemsNuevos, {
    required String numeroTalonario,
    required int sumadoCentavos,
    required DateTime ahora,
    String? motivoMontoManual,
    int? diferenciaCentavos,
  });
}
