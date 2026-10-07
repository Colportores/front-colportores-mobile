import 'dart:async';

import 'package:http/http.dart' as http;

import '../../domain/services/puertos_descarga.dart';
import 'falla_de_red.dart';

/// [ClienteDescargaRango] con `package:http` (decisión d4 de #189): un GET con
/// `Range: bytes=<desde>-` y el cuerpo como flujo, sin cargar el archivo en memoria.
///
/// - **206**: respetó el `Range`; el cuerpo viene desde el byte de `Content-Range`. Un 206 sin ese
///   encabezado (o ilegible) es un error del servidor: no se sabe desde dónde viene.
/// - **200**: no soporta `Range` y manda el archivo entero (`desde` 0).
/// - Cualquier otro código (404, 416, 5xx…) lanza [ErrorServidorTiles].
/// - Sin red, DNS, TLS o un tiempo agotado antes de la respuesta lanza [ErrorRedTiles]. Si el
///   servidor se queda callado a mitad del cuerpo ([esperaPedazo]), el flujo termina con un
///   [ErrorRedTiles] y la descarga queda en pausa con lo bajado.
///
/// Pide `Accept-Encoding: identity`: los bytes del `Range` y el checksum son los del archivo, no
/// los de una versión comprimida.
final class ClienteDescargaRangoHttp implements ClienteDescargaRango {
  ClienteDescargaRangoHttp({
    required this._cliente,
    this.esperaRespuesta = const Duration(seconds: 30),
    this.esperaPedazo = const Duration(seconds: 30),
  });

  final http.Client _cliente;

  /// Cuánto se espera la respuesta (encabezados) del servidor.
  final Duration esperaRespuesta;

  /// Cuánto se espera entre un pedazo del cuerpo y el siguiente.
  final Duration esperaPedazo;

  static final _contentRange = RegExp(r'^bytes (\d+)-(\d+)/(\d+|\*)$');

  @override
  Future<RespuestaDescarga> pedir(Uri origen, {required int desde}) async {
    final pedido = http.Request('GET', origen)..headers['accept-encoding'] = 'identity';
    if (desde > 0) pedido.headers['range'] = 'bytes=$desde-';
    final http.StreamedResponse respuesta;
    try {
      respuesta = await _cliente.send(pedido).timeout(esperaRespuesta);
    } on Object catch (e) {
      if (esFallaDeRed(e)) throw ErrorRedTiles(e);
      rethrow;
    }
    switch (respuesta.statusCode) {
      case 206:
        final inicio = _inicioDe(respuesta.headers['content-range']);
        if (inicio == null) {
          await _soltar(respuesta);
          throw const ErrorServidorTiles(206);
        }
        return RespuestaDescarga(desde: inicio, bytes: _cuerpo(respuesta));
      case 200:
        return RespuestaDescarga(desde: 0, bytes: _cuerpo(respuesta));
      default:
        await _soltar(respuesta);
        throw ErrorServidorTiles(respuesta.statusCode);
    }
  }

  /// El byte en que empieza el cuerpo de un 206: `bytes <inicio>-<fin>/<total>`.
  static int? _inicioDe(String? contentRange) {
    final coincidencia = contentRange == null
        ? null
        : _contentRange.firstMatch(contentRange.trim());
    return coincidencia == null ? null : int.tryParse(coincidencia.group(1)!);
  }

  /// El cuerpo, con un tope de silencio entre pedazos: si el servidor se calla, el flujo termina con
  /// [ErrorRedTiles]. Un corte de la conexión a mitad del cuerpo llega tal cual (por ejemplo una
  /// `SocketException`): para el descargador, cualquier error del flujo es un corte y pausa la
  /// bajada hasta que vuelva la red.
  Stream<List<int>> _cuerpo(http.StreamedResponse respuesta) {
    return respuesta.stream.timeout(
      esperaPedazo,
      onTimeout: (sink) {
        sink
          ..addError(ErrorRedTiles(TimeoutException('sin datos', esperaPedazo)))
          ..close();
      },
    );
  }

  /// Cierra la conexión de una respuesta que no se va a leer, sin bajar el cuerpo.
  static Future<void> _soltar(http.StreamedResponse respuesta) async {
    await respuesta.stream.listen(null).cancel();
  }
}
