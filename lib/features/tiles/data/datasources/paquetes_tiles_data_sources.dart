import '../../domain/entities/paquete_tiles.dart';

/// De dónde sale el catálogo de paquetes PMTiles (HU-SYNC-010): el `catalogo.json` del bucket
/// público `mapas` de Supabase Storage (`CatalogoPaquetesTilesHttp`).
/// `CatalogoPaquetesTilesEnMemoria` sirve para los tests y para el modo demo sin Supabase.
abstract interface class CatalogoPaquetesTilesRemoteDataSource {
  /// Lanza `ErrorRedTiles` sin red, `ErrorServidorTiles` si el servidor responde con error y
  /// `FormatException` si lo que devuelve no es un catálogo que la app entienda.
  Future<List<PaqueteTiles>> listar();
}

/// Dónde queda anotado qué paquetes están descargados y validados (HU-SYNC-010): un manifiesto
/// JSON junto a los `.pmtiles` (`RegistroPaquetesDescargadosJson`, decisión d7 de #189).
/// `RegistroPaquetesDescargadosEnMemoria` sirve para los tests y para el modo demo.
abstract interface class RegistroPaquetesDescargadosLocalDataSource {
  Future<List<PaqueteDescargado>> leer();

  /// Reemplaza al anterior con el mismo id.
  Future<void> guardar(PaqueteDescargado descargado);

  /// Si no estaba, no hace nada.
  Future<void> quitar(String paqueteId);
}
