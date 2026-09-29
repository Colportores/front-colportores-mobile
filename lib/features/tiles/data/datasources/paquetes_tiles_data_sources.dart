import '../../domain/entities/paquete_tiles.dart';

/// De dónde sale el catálogo de paquetes PMTiles (HU-SYNC-010).
///
/// Sin implementación real: la documentación no fija dónde se publica el catálogo ni su formato
/// (una tabla o vista en `backend-supabase`, un JSON en el bucket junto a los `.pmtiles`, ...).
/// Queda anotado en el issue #189. `CatalogoPaquetesTilesEnMemoria` sirve para los tests y para
/// el modo demo.
abstract interface class CatalogoPaquetesTilesRemoteDataSource {
  /// Lanza `ErrorRedTiles` sin red y `ErrorServidorTiles` si el servidor responde con error.
  Future<List<PaqueteTiles>> listar();
}

/// Dónde queda anotado qué paquetes están descargados y validados (HU-SYNC-010).
///
/// Sin implementación persistente: elegir dónde (una tabla de Drift en la DB local, con su
/// migración, o un manifiesto JSON junto a los `.pmtiles`) es decisión de Cristian (issue #189).
/// `RegistroPaquetesDescargadosEnMemoria` sirve para los tests y para el modo demo.
abstract interface class RegistroPaquetesDescargadosLocalDataSource {
  Future<List<PaqueteDescargado>> leer();

  /// Reemplaza al anterior con el mismo id.
  Future<void> guardar(PaqueteDescargado descargado);

  /// Si no estaba, no hace nada.
  Future<void> quitar(String paqueteId);
}
