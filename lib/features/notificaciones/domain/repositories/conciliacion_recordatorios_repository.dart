import '../../../agenda/domain/entities/recordatorio_de_visita.dart';

/// Las visitas agendadas cuyo recordatorio ya tuvo que sonar (HU-NOT-005: «cada recordatorio local
/// se guarda al dispararse»). Solo lee.
abstract interface class AgendasConAvisoVencido {
  /// Las agendas de [colportorId], sin baja, cuyo aviso (la visita menos [anticipacionMinutos]) cae
  /// después de [desde] y hasta [hasta] inclusive, y cuyo recordatorio **valía a la hora del
  /// aviso**: una `PROGRAMADA` que ya existía y no se cambió después (una agenda guardada con menos
  /// tiempo que la anticipación nunca tuvo recordatorio), o una `CUMPLIDA` / `NO_CUMPLIDA` cuyo
  /// resultado se guardó después del aviso. Una `CANCELADA` nunca. Con la dirección que va en el
  /// aviso. Lanza si no se puede leer.
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
