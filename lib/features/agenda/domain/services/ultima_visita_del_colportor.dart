/// La hora de la visita anterior de una colportora: de ahí sale la entrada de una entrevista cuyo
/// inicio no se registró (vista 39, R·07; flujo lógico §6.1).
abstract interface class UltimaVisitaDelColportor {
  /// La fecha de la última visita de [colportorId] **anterior a** [antesDe], o `null` si no tiene
  /// (nunca se inventa una hora). Las visitas dadas de baja no cuentan.
  Future<DateTime?> fechaAntesDe(String colportorId, DateTime antesDe);
}
