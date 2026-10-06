import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../domain/repositories/paquetes_tiles_repository.dart';
import '../domain/services/descargador_paquetes_tiles.dart';
import '../domain/services/puertos_descarga.dart';
import 'datasources/catalogo_paquetes_tiles_http.dart';
import 'datasources/fakes/paquetes_tiles_en_memoria.dart';
import 'datasources/paquetes_tiles_data_sources.dart';
import 'datasources/registro_paquetes_descargados_json.dart';
import 'repositories/paquetes_tiles_repository_impl.dart';
import 'services/almacenamiento_tiles_canal.dart';
import 'services/archivos_tiles_io.dart';
import 'services/calculador_checksum_sha256.dart';
import 'services/cliente_descarga_rango_http.dart';

/// Arma el repositorio y el descargador de paquetes de mapas con los adaptadores reales
/// (`main.dart` los pone en los providers de `tiles_providers.dart`).
///
/// Los paquetes viven en `<directorio de soporte de la app>/tiles`: almacenamiento interno (la
/// capa nativa de MapLibre solo lee de ahí) y fuera de la copia de seguridad.
final class ComposicionTiles {
  ComposicionTiles._({
    required this.repository,
    required this.descargador,
    required this.directorio,
    required this.reconciliacion,
  });

  final PaquetesTilesRepository repository;
  final DescargadorPaquetesTiles descargador;

  /// La carpeta de los `.pmtiles`, los `.part` y el manifiesto.
  final Directory directorio;

  /// Termina cuando la limpieza de arranque (`PaquetesTilesRepository.reconciliar`) terminó. La
  /// app no la espera: corre en segundo plano.
  final Future<void> reconciliacion;

  /// Crea la carpeta de los paquetes, la saca de la copia de seguridad, arma todo y lanza la
  /// reconciliación de lo que quedó en disco de la sesión anterior.
  ///
  /// [supabaseUrl] es la del proyecto; el catálogo sale de su bucket público `mapas`. Sin ella (la
  /// app sin Supabase: tests, demo) el catálogo está vacío y no hay nada para descargar.
  static Future<ComposicionTiles> crear({
    required Directory directorioApp,
    required MonitorConectividad conectividad,
    required String supabaseUrl,
    http.Client? cliente,
    MethodChannel? canal,
  }) async {
    final directorio = Directory(p.join(directorioApp.path, 'tiles'));
    await directorio.create(recursive: true);
    final almacenamiento = AlmacenamientoTilesCanal(directorio, canal: canal);
    await almacenamiento.excluirDeBackup();

    final http.Client web = cliente ?? http.Client();
    final CatalogoPaquetesTilesRemoteDataSource catalogo = supabaseUrl.isEmpty
        ? CatalogoPaquetesTilesEnMemoria()
        : CatalogoPaquetesTilesHttp(
            cliente: web,
            url: CatalogoPaquetesTilesHttp.urlDeSupabase(supabaseUrl),
          );
    final archivos = ArchivosTilesIo(directorio);
    const checksum = CalculadorChecksumSha256();
    final repository = PaquetesTilesRepositoryImpl(
      catalogo: catalogo,
      registro: RegistroPaquetesDescargadosJson(directorio),
      archivos: archivos,
      checksum: checksum,
    );
    final descargador = DescargadorPaquetesTiles(
      conectividad: conectividad,
      espacio: almacenamiento,
      cliente: ClienteDescargaRangoHttp(cliente: web),
      archivos: archivos,
      checksum: checksum,
      repository: repository,
    );
    return ComposicionTiles._(
      repository: repository,
      descargador: descargador,
      directorio: directorio,
      reconciliacion: repository.reconciliar().then((_) {}),
    );
  }
}
