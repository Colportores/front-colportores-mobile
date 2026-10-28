import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../entities/entrega.dart';
import '../entities/entrega_diferida.dart';
import '../entities/entrega_pendiente.dart';

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

  /// Deja lo que falta entregar de la venta [ventaId] para [fechaPrevista] (HU-VEN-003, «Entrega
  /// diferida» y «Poner fecha»), con su cita `ENTREGA` en la agenda. Todo en una transacción: las
  /// filas, la cita, sus jobs de sync y el color de la casa.
  ///
  /// - Una venta **sin filas de entrega** guarda [filasNuevas] (una por producto, pendientes y con la
  ///   fecha); una que ya tiene filas pendientes les pone la fecha ([filasNuevas] no se usa).
  /// - Si la venta ya tenía una cita `PROGRAMADA`, se la **mueve** a la fecha nueva en vez de crear
  ///   otra ([idDeLaCita] solo se usa al crearla). Repetir la misma fecha no escribe nada
  ///   ([EntregaDiferida.yaEstaba]).
  /// - Una venta sin nada pendiente, que no está en el teléfono o cuya casa no está, no guarda nada.
  Future<Either<Failure, EntregaDiferida>> diferir(
    String ventaId, {
    required DateTime fechaPrevista,
    required DateTime ahora,
    required List<Entrega> filasNuevas,
    required String idDeLaCita,
  });

  /// Marca como entregado, con la fecha real [ahora], lo pendiente de la venta [ventaId] (HU-VEN-003,
  /// «Cumplir entrega pendiente»). Todo en una transacción: las filas, la cita, sus jobs de sync y el
  /// color de la casa.
  ///
  /// - [entregaIds] son las filas que se entregan (27C·04, entrega parcial); `null`: todo lo
  ///   pendiente. Lo que no se entrega sigue pendiente, con [nuevaFecha] si la hay y **sin fecha** si
  ///   no (27C·04, «Sin fecha»). Con [nuevaFecha] y una venta sin cita se agenda una ([idDeLaCita]).
  /// - La cita `PROGRAMADA` de la venta pasa a `CUMPLIDA` si no queda nada pendiente o si lo que queda
  ///   no tiene fecha nueva; con [nuevaFecha] se queda `PROGRAMADA` y se mueve a ella.
  /// - Repetir la llamada con lo ya entregado no escribe nada ([EntregaCumplida.yaEstaba]). Una venta
  ///   sin filas o con una fila que no es suya es un `FailureValidacion`.
  Future<Either<Failure, EntregaCumplida>> cumplir(
    String ventaId, {
    required DateTime ahora,
    required String idDeLaCita,
    Set<String>? entregaIds,
    DateTime? nuevaFecha,
  });

  /// Lo que falta entregar, una entrada por venta, de la más próxima a la más lejana y al final las que
  /// no tienen fecha (27C·02). Con [espacioPersonaId], solo las de esa persona (la ficha, vista 32).
  /// Reactivo y solo del teléfono: emite de nuevo cuando cambia una entrega, una venta o una cita. Un
  /// error al leer sale por el `Stream`.
  Stream<List<EntregaPendiente>> observarPendientes({String? espacioPersonaId});
}
