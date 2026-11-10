import '../entities/ultima_visita_del_espacio.dart';

/// De dónde sale el renglón «Última visita» de la hoja «Reactivar» (vista 09·03, HU-UBI-005): la última
/// visita de **cualquier** espacio de la ubicación. Local: las visitas viven en el teléfono.
abstract interface class LectorUltimaVisitaDeLaUbicacion {
  /// La visita de fecha más reciente (sin las dadas de baja) de los espacios de [ubicacionId]. `null`
  /// si no tiene ninguna: el renglón no se dibuja, no se inventa una. Un error de lectura sale como
  /// excepción.
  Future<UltimaVisitaDelEspacio?> de(String ubicacionId);
}
