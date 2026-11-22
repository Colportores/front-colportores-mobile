import '../entities/ultima_visita_del_espacio.dart';

/// De dónde sale la última visita de un espacio (el estado que lleva la ficha del depto, vista 11·04).
/// Local: las visitas viven en el teléfono.
abstract interface class LectorUltimaVisitaDelEspacio {
  /// La última visita (la de fecha más reciente, sin las dadas de baja) del espacio [espacioId], al día
  /// cuando se registra o se deshace una. `null` si el espacio no tiene ninguna: no se inventa un
  /// estado. Un error de lectura sale por el `Stream`.
  Stream<UltimaVisitaDelEspacio?> observar(String espacioId);
}
