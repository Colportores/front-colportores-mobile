import '../entities/item_agenda.dart';

/// La lectura de la agenda del colportor (HU-VIS-002): reactiva, solo del teléfono (funciona sin
/// conexión).
///
/// Es aparte de `AgendaRepository` (que escribe) porque lee y emite: la pantalla de la agenda se
/// repinta sola cuando se agenda, se cancela o se registra una visita (stream-first, §8.8).
abstract interface class ConsultaAgendaRepository {
  /// Las agendas de [colportorId] sin baja con `fecha_programada` entre [desde] (incluido) y [hasta]
  /// (excluido), en **cualquier estado**, de la más temprana a la más tardía, con la persona y la
  /// dirección de cada una. Emite de nuevo cada vez que cambia una agenda, una persona o una
  /// ubicación involucrada. Un error al leer sale por el `Stream`.
  Stream<List<ItemAgenda>> observar({
    required String colportorId,
    required DateTime desde,
    required DateTime hasta,
  });
}
