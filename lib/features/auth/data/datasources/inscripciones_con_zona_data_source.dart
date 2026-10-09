import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/inscripcion_con_zona.dart';

/// De dónde salen las inscripciones propias del colportor con el nombre de su campaña y de su zona,
/// para avisarle cuando el coordinador le asigna, le cambia o le quita la zona (HU-CAM-006, #251,
/// decisión de Cristian, 30/09, front-coordinadores-web#20).
///
/// La fuente de verdad es el pull de catálogos: `campania_colportor` (solo las propias, por RLS)
/// baja junto con el mapa de la campaña, y el nombre de la zona sale de la réplica de `zona`. El
/// adaptador sobre esas réplicas llega con el motor de sincronización (mobile#180) y la lectura del
/// pull (mobile#274); hasta entonces no hay fuente y no se inventa nada ([InscripcionesConZonaSinFuente]).
abstract interface class InscripcionesConZonaDataSource {
  /// Las inscripciones de [usuarioId], completas, cada vez que la réplica cambia: emite el estado
  /// actual al suscribirse y uno nuevo cuando un pull termina de escribir. Incluye las dadas de
  /// baja ([InscripcionConZona.dadaDeBaja]): el detector las anota sin avisar.
  ///
  /// No lanza al suscribirse: una lectura que falla se reporta como error del *stream*.
  Stream<List<InscripcionConZona>> observar(String usuarioId);
}

/// Mientras no lleguen el motor de sincronización y la lectura del pull (mobile#180 y #274): no hay
/// de dónde sacar las inscripciones, así que no hay avisos. **No es la regla de la HU**: se
/// reemplaza por la lectura de las réplicas cuando exista. Deja un `warn` por suscripción para que
/// no pase inadvertido en el log.
final class InscripcionesConZonaSinFuente implements InscripcionesConZonaDataSource {
  InscripcionesConZonaSinFuente({AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  @override
  Stream<List<InscripcionConZona>> observar(String usuarioId) {
    _log.warn(
      LogModulo.auth,
      'ZONA_AVISO_SIN_FUENTE',
      'sin fuente de las inscripciones con zona: no hay avisos de zona hasta el pull (#274)',
    );
    return Stream.value(const <InscripcionConZona>[]);
  }
}
