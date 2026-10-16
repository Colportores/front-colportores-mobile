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
/// - El pedido es un `AbortableRequest`: al vencer la espera y cuando [probar] recibe su
///   `cancelacion` se **aborta** y la conexión se cierra. Sin eso, `Future.timeout` solo deja de
///   esperar y cada apertura del mapa contra un servidor que no contesta dejaba una conexión abierta.
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
  Future<void> probar(Uri origen, {Future<void>? cancelacion}) async {
    final abortar = Completer<void>();
    var terminada = false;
    // Abortar después de que la prueba terminó no hace nada (y no se intenta): la respuesta ya se
    // soltó.
    void abortarElPedido() {
      if (!terminada && !abortar.isCompleted) abortar.complete();
    }

    if (cancelacion != null) {
      unawaited(cancelacion.then((_) => abortarElPedido(), onError: (Object _) {}));
    }
    final pedido = http.AbortableRequest('GET', origen, abortTrigger: abortar.future)
      ..headers['accept-encoding'] = 'identity'
      ..headers['range'] = 'bytes=0-0';
    try {
      final enVuelo = _cliente.send(pedido);
      final http.StreamedResponse respuesta;
      try {
        respuesta = await enVuelo.timeout(esperaRespuesta);
      } on Object catch (e) {
        if (e is TimeoutException) {
          // Se corta el pedido que quedó colgado. Si el cliente no sabe abortar y la respuesta
          // llega después del tiempo, nadie la lee: se suelta para no dejar la conexión abierta
          // (un 200 podría ser el archivo entero).
          abortarElPedido();
          unawaited(enVuelo.then(_soltar, onError: (Object _) {}));
        }
        if (esFallaDeRed(e)) throw ErrorRedTiles(e);
        rethrow;
      }
      await _soltar(respuesta);
      if (respuesta.statusCode != 206 && respuesta.statusCode != 200) {
        throw ErrorServidorTiles(respuesta.statusCode);
      }
    } finally {
      terminada = true;
    }
  }

  /// Cierra la conexión de una respuesta que no se va a leer, sin bajar el cuerpo. El error vacío
  /// es por si el pedido se abortó justo antes: `package:http` lo inyecta en el cuerpo al escucharlo
  /// y, sin quien lo atrape, escaparía como error sin manejar.
  static Future<void> _soltar(http.StreamedResponse respuesta) async {
    try {
      await respuesta.stream.listen(null, onError: (Object _) {}).cancel();
    } on Object {
      // Ya se sabe qué contestó el servidor: que no se pueda cerrar el cuerpo no cambia la respuesta.
    }
  }
}
