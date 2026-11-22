import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/paquete_tiles.dart';
import '../../domain/services/puertos_descarga.dart';
import '../models/catalogo_tiles_model.dart';
import '../services/falla_de_red.dart';
import 'paquetes_tiles_data_sources.dart';

/// El catálogo de paquetes leído de `catalogo.json` en el bucket público `mapas` (HU-SYNC-010,
/// ADR-011): un GET sin login (`<SUPABASE_URL>/storage/v1/object/public/mapas/catalogo.json`) y
/// directo a Storage, sin pasar por el BFF.
///
/// Las rutas de las partes son relativas a [_url]; `CatalogoTilesModel` las resuelve. Un paquete
/// del catálogo que no cumple el contrato se descarta y queda en el log (`[MAP]`), sin tirar el
/// resto.
final class CatalogoPaquetesTilesHttp implements CatalogoPaquetesTilesRemoteDataSource {
  CatalogoPaquetesTilesHttp({
    required this._cliente,
    required this._url,
    this.tiempoMaximo = tiempoMaximoPorDefecto,
    AppLogger? logger,
  }) : _logger = logger ?? AppLogger.instance;

  /// El catálogo de un proyecto Supabase: `<url>/storage/v1/object/public/mapas/catalogo.json`.
  static Uri urlDeSupabase(String supabaseUrl) {
    final base = supabaseUrl.endsWith('/')
        ? supabaseUrl.substring(0, supabaseUrl.length - 1)
        : supabaseUrl;
    return Uri.parse('$base/storage/v1/object/public/mapas/catalogo.json');
  }

  /// Tope para recibir el catálogo entero (la respuesta y cada pedazo). Pesa unos pocos KB.
  static const Duration tiempoMaximoPorDefecto = Duration(seconds: 20);

  /// El catálogo no pasa de unos KB: un cuerpo más grande no es el catálogo.
  static const topeBytes = 1024 * 1024;

  final http.Client _cliente;
  final Uri _url;
  final Duration tiempoMaximo;
  final AppLogger _logger;

  @override
  Future<List<PaqueteTiles>> listar() async {
    final List<int> cuerpo;
    try {
      cuerpo = await _pedir();
    } on Object catch (e) {
      if (esFallaDeRed(e)) throw ErrorRedTiles(e);
      rethrow;
    }
    return CatalogoTilesModel.desdeJson(
      utf8.decode(cuerpo),
      _url,
      descartado: (id, motivo) => _logger.warn(LogModulo.map, 'catalogo', 'paquete descartado', {
        'paquete': id ?? '?',
        'motivo': motivo,
      }),
    );
  }

  Future<List<int>> _pedir() async {
    final pedido = http.Request('GET', _url)
      ..headers['accept'] = 'application/json'
      ..headers['accept-encoding'] = 'identity';
    final respuesta = await _cliente.send(pedido).timeout(tiempoMaximo);
    if (respuesta.statusCode != 200) {
      await respuesta.stream.listen(null).cancel();
      throw ErrorServidorTiles(respuesta.statusCode);
    }
    final cuerpo = <int>[];
    await for (final pedazo in respuesta.stream.timeout(tiempoMaximo)) {
      cuerpo.addAll(pedazo);
      if (cuerpo.length > topeBytes) throw const FormatException('el catálogo es demasiado grande');
    }
    return cuerpo;
  }
}
