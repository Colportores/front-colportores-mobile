// El camino batch hacia `bff-colportores` (§6).
//
// Único lugar del paquete que sabe qué es HTTP. El formato de los mensajes está
// en docs/formato-de-cable.md; acá se implementa y se traduce a los tipos del
// núcleo.
//
// R-A1: este archivo vive en adapters/ porque toca el mundo. `package:http` es
// Dart puro, así que igual se testea en la VM con un MockClient.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/model.dart';
import '../core/ports.dart';
import '../core/wire.dart';

/// `SyncTransport` sobre HTTP/JSON contra el BFF.
class BffTransport implements SyncTransport {
  BffTransport({
    required Uri baseUrl,
    required this.token,
    required this.device,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  })  : _base = baseUrl,
        _client = client ?? http.Client();

  final Uri _base;

  /// El sobre de §5.3. Es del transporte y no del lote porque no cambia entre
  /// ciclos: identifica a esta instalación, no a lo que sube.
  final ClientEnvelope device;

  /// El JWT vigente. El motor **no** gestiona la sesión (§10): la app le pasa
  /// una función y se encarga del refresh por su lado.
  final Future<String?> Function() token;

  final http.Client _client;
  final Duration timeout;

  @override
  Future<PushResult> push(PushBatch batch) async {
    final cuerpo = await _pedir(
      // El cuerpo lo arma el codec compartido, no este archivo: si se
      // escribiera acá a mano, sería la segunda implementación del mismo JSON y
      // podría separarse de la que el BFF parsea sin que nada lo note.
      () async => _client.post(
        _base.resolve('sync/push'),
        headers: await _headers(json: true),
        body: jsonEncode(pushRequestToJson(batch, device)),
      ),
    );

    return pushResponseFromJson(cuerpo);
  }

  @override
  Future<PullDelta> pull({
    required List<String> entities,
    String? watermark,
    int? limit,
  }) async {
    final uri = _base.resolve('sync/pull').replace(queryParameters: {
      'entities': entities.join(','),
      if (watermark != null) 'watermark': watermark,
      if (limit != null) 'limit': '$limit',
      ...envelopeToQuery(device),
    });

    final cuerpo = await _pedir(
      () async => _client.get(uri, headers: await _headers()),
    );

    return pullResponseFromJson(cuerpo, watermarkPrevio: watermark);
  }

  void close() => _client.close();

  // --- traducción -------------------------------------------------------------

  Future<Map<String, String>> _headers({bool json = false}) async {
    final jwt = await token();
    return {
      if (jwt != null) 'Authorization': 'Bearer $jwt',
      'Accept': 'application/json',
      if (json) 'Content-Type': 'application/json; charset=utf-8',
    };
  }

  /// Hace la llamada y devuelve el cuerpo, o lanza [TransportFailure].
  ///
  /// Ninguna excepción de `package:http` escapa de acá: el núcleo no sabría
  /// clasificarla, y clasificar es lo que decide entre `PENDING` e `INVALID`.
  Future<Map<String, Object?>> _pedir(
      Future<http.Response> Function() llamada) async {
    final http.Response respuesta;
    try {
      respuesta = await llamada().timeout(timeout);
    } on TimeoutException {
      throw const TransportFailure(FailureKind.transient,
          code: 'TIMEOUT', message: 'el BFF no respondió a tiempo');
    } on http.ClientException catch (e) {
      throw TransportFailure(FailureKind.transient,
          code: 'SIN_RED', message: e.message);
    }

    if (respuesta.statusCode >= 300) {
      throw _falla(respuesta);
    }

    try {
      return jsonDecode(utf8.decode(respuesta.bodyBytes))
          as Map<String, Object?>;
    } on Object {
      // Un cuerpo ilegible es un bug del servidor. Mandar a INVALID un job que
      // estaba bien porque el BFF devolvió basura sería peor que reintentarlo.
      throw const TransportFailure(FailureKind.transient,
          code: 'RESPUESTA_ILEGIBLE',
          message: 'el BFF respondió algo que no es JSON');
    }
  }

  TransportFailure _falla(http.Response r) {
    var codigo = 'HTTP_${r.statusCode}';
    var mensaje = '';
    try {
      final cuerpo = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
      codigo = (cuerpo['code'] as String?) ?? codigo;
      mensaje = (cuerpo['message'] as String?) ?? '';
    } on Object {
      // Un error sin cuerpo JSON sigue siendo un error: el status alcanza.
    }

    return TransportFailure.fromStatus(
      r.statusCode,
      code: codigo,
      message: mensaje,
      retryAfter: _retryAfter(r.headers['retry-after']),
    );
  }

  /// `Retry-After` en segundos. La forma con fecha HTTP no se soporta: el BFF
  /// es nuestro y manda segundos.
  static Duration? _retryAfter(String? valor) {
    if (valor == null) return null;
    final segundos = int.tryParse(valor.trim());
    return segundos == null ? null : Duration(seconds: segundos);
  }
}
