/// Cuántas personas activas tiene un espacio (`espacio_persona`, ADR-001).
///
/// Puerto de la baja de espacios (HU-UBI-007): la tabla de personas la trae HU-UBI-008, así que
/// hoy no hay adaptador de producción y los tests usan un fake (decisión anotada en el issue #210).
abstract interface class ContadorPersonasEspacio {
  /// Personas activas (no dadas de baja) vinculadas a [espacioId].
  Future<int> activasEn(String espacioId);
}
