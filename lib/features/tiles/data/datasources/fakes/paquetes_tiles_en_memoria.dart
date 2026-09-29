import '../../../domain/entities/paquete_tiles.dart';
import '../../../domain/services/puertos_descarga.dart';
import '../paquetes_tiles_data_sources.dart';

/// Catálogo fijo en memoria, para los tests y el modo demo mientras no haya catálogo real
/// (issue #189). [sinRed] y [statusError] simulan las fallas del remoto.
final class CatalogoPaquetesTilesEnMemoria implements CatalogoPaquetesTilesRemoteDataSource {
  CatalogoPaquetesTilesEnMemoria([this.paquetes = const []]);

  List<PaqueteTiles> paquetes;
  bool sinRed = false;
  int? statusError;

  @override
  Future<List<PaqueteTiles>> listar() async {
    if (sinRed) throw const ErrorRedTiles();
    if (statusError case final status?) throw ErrorServidorTiles(status);
    return List.unmodifiable(paquetes);
  }
}

/// Registro en memoria de los paquetes descargados, en orden de registro. [fallarCon] hace que
/// todas las operaciones lancen.
final class RegistroPaquetesDescargadosEnMemoria
    implements RegistroPaquetesDescargadosLocalDataSource {
  final _porId = <String, PaqueteDescargado>{};
  Object? fallarCon;

  @override
  Future<List<PaqueteDescargado>> leer() async {
    _quizasFallar();
    return List.unmodifiable(_porId.values);
  }

  @override
  Future<void> guardar(PaqueteDescargado descargado) async {
    _quizasFallar();
    _porId[descargado.id] = descargado;
  }

  @override
  Future<void> quitar(String paqueteId) async {
    _quizasFallar();
    _porId.remove(paqueteId);
  }

  void _quizasFallar() {
    if (fallarCon case final error?) throw error;
  }
}
