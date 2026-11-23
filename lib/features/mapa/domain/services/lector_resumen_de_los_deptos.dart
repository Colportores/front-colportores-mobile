import '../entities/resumen_del_depto.dart';

/// De dónde sale lo que dice cada fila de la hoja del edificio (vista 39, C·09): el estado de cada
/// depto, su última visita y su próxima entrevista. Solo lee.
abstract interface class LectorResumenDeLosDeptos {
  /// El resumen de cada espacio activo de [ubicacionId] (`espacio.id` → resumen), al día: vuelve a
  /// emitir cuando se registra una visita, se agenda, se vende o se cobra en cualquiera de ellos, o
  /// cuando se suma o se da de baja un depto. La próxima entrevista es la de [colportorId] (sin él,
  /// ninguna). Una falla de lectura sale por el `Stream`.
  Stream<Map<String, ResumenDelDepto>> observar(String ubicacionId, {String? colportorId});
}
