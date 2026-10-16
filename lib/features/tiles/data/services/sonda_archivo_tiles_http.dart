import 'dart:async';

import 'package:http/http.dart' as http;

import '../../domain/services/puertos_descarga.dart';
import 'cliente_descarga_rango_http.dart';
import 'falla_de_red.dart';

/// [SondaArchivoTiles] con `package:http` (#299, «Mapa caído» de HU-SYNC-010): un GET con
/// `Range: bytes=0-0` al `.pmtiles`, igual que el que hace MapLibre para leer el mapa en línea, y
/// nada más: el cuerpo no se lee.
///
/// - **206** o **200**: el servidor contestó. Un 200 es un servidor que ignora el `Range` y manda el
///   archivo entero; se corta la conexión sin bajar nada.
/// - Cualquier otro código (404, 403, 416, 5xx…) lanza [ErrorServidorTiles].
/// - Sin red, DNS, TLS o sin respuesta en [esperaRespuesta] lanza [ErrorRedTiles]. La espera es la
///   del descargador ([ClienteDescargaRangoHttp.esperaRespuestaPorDefecto]).
///
/// Pide `Accept-Encoding: identity`, como el descargador: el byte pedido es del archivo, no de una
/// versión comprimida.
final class SondaArchivoTilesHttp implements SondaArchivoTiles {
  SondaArchivoTilesHttp({
    required this._cliente,
    this.esperaRespuesta = ClienteDescargaRangoHttp.esperaRespuestaPorDefecto,
  });

  final http.Client _cliente;

  /// Cuánto se espera la respuesta (encabezados) del servidor.
  final Duration esperaRespuesta;

  @override
  Future<void> probar(Uri origen) async {
    final pedido = http.Request('GET', origen)
      ..headers['accept-encoding'] = 'identity'
      ..headers['range'] = 'bytes=0-0';
    final enVuelo = _cliente.send(pedido);
    final http.StreamedResponse respuesta;
    try {
      respuesta = await enVuelo.timeout(esperaRespuesta);
    } on Object catch (e) {
      // Si la respuesta llega después del tiempo, nadie la lee: se suelta para no dejar la
      // conexión abierta (un 200 podría ser el archivo entero).
      if (e is TimeoutException) unawaited(enVuelo.then(_soltar, onError: (Object _) {}));
      if (esFallaDeRed(e)) throw ErrorRedTiles(e);
      rethrow;
    }
    await _soltar(respuesta);
    if (respuesta.statusCode != 206 && respuesta.statusCode != 200) {
      throw ErrorServidorTiles(respuesta.statusCode);
    }
  }

  /// Cierra la conexión de una respuesta que no se va a leer, sin bajar el cuerpo.
  static Future<void> _soltar(http.StreamedResponse respuesta) async {
    try {
      await respuesta.stream.listen(null).cancel();
    } on Object {
      // Ya se sabe qué contestó el servidor: que no se pueda cerrar el cuerpo no cambia la respuesta.
    }
  }
}
