import '../../../cobranzas/domain/entities/cobranza.dart';
import '../entities/item_del_historial.dart';

/// Lo que ve «Mis tickets» (vista 38B, HU-COB-009): todo sale de la base del teléfono, así que se ve
/// sin conexión. Es una lectura aparte de [TicketRepository]: no escribe nada.
abstract interface class HistorialDeTicketsRepository {
  /// El historial del colportor, de nuevo cada vez que cambia un depósito, un ticket, la copia de una
  /// foto o la última bajada del servidor. Si la base no se puede leer, el `Stream` falla (la pantalla
  /// muestra 38B·07 con «Reintentar»).
  Stream<HistorialDeTickets> observar();

  /// El cobro con tarjeta [cobroId] tal como está en el teléfono, o `null` si ya no está vivo (se anuló,
  /// se dio de baja o no baja de este teléfono). Es de donde «Cargar de nuevo» (38B·02) saca lo que
  /// precarga en la foto del ticket (vista 29 C).
  Future<Cobranza?> cobroConTarjeta(String cobroId);
}
