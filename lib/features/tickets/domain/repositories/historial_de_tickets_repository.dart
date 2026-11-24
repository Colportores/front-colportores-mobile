import '../entities/item_del_historial.dart';

/// Lo que ve «Mis tickets» (vista 38B, HU-COB-009): todo sale de la base del teléfono, así que se ve
/// sin conexión. Es una lectura aparte de [TicketRepository]: no escribe nada.
abstract interface class HistorialDeTicketsRepository {
  /// El historial del colportor, de nuevo cada vez que cambia un depósito, un ticket, la copia de una
  /// foto o la última bajada del servidor. Si la base no se puede leer, el `Stream` falla (la pantalla
  /// muestra 38B·07 con «Reintentar»).
  Stream<HistorialDeTickets> observar();
}
