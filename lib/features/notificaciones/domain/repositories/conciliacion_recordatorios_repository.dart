import '../../../agenda/domain/entities/recordatorio_de_visita.dart';

/// Las visitas agendadas cuyo recordatorio ya tuvo que sonar (HU-NOT-005: «cada recordatorio local
/// se guarda al dispararse»). Solo lee.
abstract interface class AgendasConAvisoVencido {
  /// Las agendas `PROGRAMADA` de [colportorId], sin baja, cuyo aviso (la visita menos
  /// [anticipacionMinutos]) cae después de [desde] y hasta [hasta] inclusive, y que **ya existían
  /// cuando ese aviso tenía que sonar**: una agenda guardada (o cambiada) después de la hora de su
  /// aviso nunca tuvo recordatorio («Falta menos de N min para la visita: no hay recordatorio»).
  /// Con la dirección que va en el aviso. Lanza si no se puede leer.
  Future<List<RecordatorioDeVisita>> conAvisoEntre({
    required String colportorId,
    required DateTime desde,
    required DateTime hasta,
    required int anticipacionMinutos,
  });
}

/// Hasta qué instante se revisaron los recordatorios que sonaron. Sin la marca, la primera revisión
/// solo la fija: lo que sonó antes de que este teléfono empezara a llevar el historial no se
/// inventa.
abstract interface class MarcaConciliacionRecordatorios {
  /// La última marca guardada, o `null` si nunca se guardó (o no se entiende). Lanza si el almacén
  /// falla.
  Future<DateTime?> leer();

  /// Guarda [hasta] como la nueva marca. Lanza si el almacén falla.
  Future<void> guardar(DateTime hasta);
}
