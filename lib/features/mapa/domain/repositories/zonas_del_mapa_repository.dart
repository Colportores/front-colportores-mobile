import '../entities/zona_del_mapa.dart';

/// Las zonas que el mapa de ubicaciones dibuja como guía visual (HU-UBI-003, #511): las que el
/// teléfono ya tiene replicadas del pull de catálogos, sin red.
abstract interface class ZonasDelMapaRepository {
  /// Las zonas de las campañas vigentes de [colportorId], cada vez que la réplica cambia: emite las
  /// actuales al suscribirse y una lista nueva cuando un pull escribe en las tablas de las que salen.
  ///
  /// - Solo zonas vivas (la zona y su `campania_ciudad` sin baja), de campañas sin baja que no
  ///   terminaron, en las que el colportor tiene una inscripción sin baja.
  /// - Una zona con una forma que no se puede leer se saltea: una zona rota no esconde a las demás.
  /// - La lista sale ordenada por `id` (estable entre emisiones).
  /// - Sin base abierta o sin zonas emite una lista vacía. Una lectura que falla llega como error
  ///   del *stream*, no al suscribirse.
  Stream<List<ZonaDelMapa>> observar(String colportorId);
}
