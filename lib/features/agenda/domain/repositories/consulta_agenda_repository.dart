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
  ///
  /// No trae la agenda de una casa o un depto dados de baja (la agenda queda guardada y vuelve si se
  /// reactivan); con la persona de baja la trae, sin nombre.
  ///
  /// Además de esa ventana, trae las `PROGRAMADA` **anteriores a [desde]** (las atrasadas: una visita
  /// que pasó de fecha y nadie registró, que sigue en «Pendientes» hasta que se registre qué pasó).
  Stream<List<ItemAgenda>> observar({
    required String colportorId,
    required DateTime desde,
    required DateTime hasta,
  });

  /// Las agendas de [colportorId] de **la campaña en curso** a [hoy] (el día, en hora local), en
  /// **cualquier estado**, de la más nueva a la más vieja, con la persona y la dirección de cada una
  /// (HU-VIS-002, «Estado cerrado o "Todas"»). Emite de nuevo cada vez que cambia una agenda, una
  /// persona, una ubicación o la campaña. Sin campaña en curso en el teléfono, el rango queda abierto
  /// ([RangoDeCampania.sinLimite]). Un error al leer sale por el `Stream`.
  Stream<List<ItemAgenda>> observarCampania({required String colportorId, required DateTime hoy});

  /// Las agendas `PROGRAMADA` de [colportorId] de la ubicación [ubicacionId] (de cualquiera de sus
  /// espacios), de la más temprana a la más tardía, con la persona y la dirección de cada una: la
  /// lista «Visitas agendadas» de la hoja de la casa (23B·10, #491). Igual que las demás lecturas, no
  /// trae la agenda de un depto o una casa dados de baja y deja sin nombre a la persona de baja. Emite
  /// de nuevo cada vez que cambia una agenda, una persona o una ubicación involucrada. Un error al
  /// leer sale por el `Stream`.
  Stream<List<ItemAgenda>> observarDeLaCasa({
    required String colportorId,
    required String ubicacionId,
  });

  /// Las agendas `PROGRAMADA` de [colportorId] con la persona [personaId] (por cualquiera de sus
  /// vínculos con un espacio), de la más temprana a la más tardía: la tarjeta «PRÓXIMA VISITA» de la
  /// ficha de la persona (vista 32, 23A·05, #405). Igual que las demás lecturas, no trae la agenda de
  /// un depto o una casa dados de baja. Emite de nuevo cada vez que cambia una agenda, la persona o una
  /// ubicación involucrada. Un error al leer sale por el `Stream`.
  Stream<List<ItemAgenda>> observarDeLaPersona({
    required String colportorId,
    required String personaId,
  });
}
