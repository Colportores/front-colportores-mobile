/// La zona de cada inscripción de la última vez que se le avisó al colportor, guardada fuera de la
/// DB (HU-CAM-006, #251). Es lo que hace que un cambio de zona se avise **una sola vez**: el
/// detector compara lo que hay en el teléfono contra esto.
///
/// Es `inscripción (campania_colportor.id) → zona (zona.id, o null si quedó sin zona)`. Una
/// inscripción que no está es una que el teléfono nunca vio. Solo ids de la app (UUID), ningún
/// nombre ni dato de persona.
///
/// Nunca lanza: si el almacén falla, leer devuelve lo que pueda (nada) y anotar queda en el log; lo
/// peor que pasa es que un aviso se repita, nunca que se pierda. Las operaciones se ejecutan **en
/// el orden en que se piden**.
abstract interface class ZonasAvisadasRepository {
  /// Lo guardado, o vacío si no hay nada (o no se pudo leer).
  Future<Map<String, String?>> leer();

  /// Anota las zonas de [avisadas] (inscripción → zona, `null` = sin zona), sin tocar las demás
  /// inscripciones ya anotadas.
  Future<void> anotar(Map<String, String?> avisadas);
}
