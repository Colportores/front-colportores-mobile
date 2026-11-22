import '../../domain/entities/inscripcion_con_zona.dart';

/// De dónde salen las inscripciones propias del colportor con el nombre de su campaña y de su zona,
/// para avisarle cuando el coordinador le asigna, le cambia o le quita la zona (HU-CAM-006, #251,
/// decisión de Cristian, 30/09, front-coordinadores-web#20).
///
/// La fuente de verdad es el pull de catálogos: `campania_colportor` (solo las propias, por RLS)
/// baja junto con el mapa de la campaña, y el nombre de la zona sale de la réplica de `zona`. El
/// adaptador sobre esas réplicas es `InscripcionesConZonaLocal` (mobile#274).
abstract interface class InscripcionesConZonaDataSource {
  /// Las inscripciones de [usuarioId], completas, cada vez que la réplica cambia: emite el estado
  /// actual al suscribirse y uno nuevo cuando un pull termina de escribir. Incluye las dadas de
  /// baja ([InscripcionConZona.dadaDeBaja]): el detector las anota sin avisar.
  ///
  /// No lanza al suscribirse: una lectura que falla se reporta como error del *stream*.
  Stream<List<InscripcionConZona>> observar(String usuarioId);
}
