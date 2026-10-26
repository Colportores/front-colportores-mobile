/// De dónde sale cuándo fue la última entrevista dada a cada persona (la línea «Entrevista dada el
/// 05/10» de la pestaña Personas de la hoja de la casa, vista 39 C·02). Local: las visitas viven en
/// el teléfono.
abstract interface class LectorEntrevistasDePersonas {
  /// Cuándo fue la última visita de entrevista (que no esté dada de baja) de cada vínculo de
  /// [vinculoIds] (`espacio_persona.id`). Quien nunca tuvo una no aparece en el mapa: no se afirma
  /// nada. Un error de lectura sale por el `Future`.
  Future<Map<String, DateTime>> ultimaEntrevistaDe(Iterable<String> vinculoIds);
}

/// Mientras no haya de dónde leerlas (los tests): no se sabe de nadie.
final class LectorEntrevistasSinFuente implements LectorEntrevistasDePersonas {
  const LectorEntrevistasSinFuente();

  @override
  Future<Map<String, DateTime>> ultimaEntrevistaDe(Iterable<String> vinculoIds) async => const {};
}
