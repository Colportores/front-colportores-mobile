// El camino batch directo a Supabase (§6, ADR-013): sin BFF en la Fase 1.
//
// El motor llama a las funciones de entrada del sync en `public`
// (`POST /rest/v1/rpc/sync_push` y `.../sync_pull`, backend-supabase 0025) con
// la anon key en `apikey` y el JWT del colportor en `Authorization`. Esas
// funciones son `security invoker`: la RLS y `auth.uid()` son las del colportor.
//
// El mensaje es el del codec (core/wire.dart), envuelto en `{"p_body": …}`, que
// es el nombre del único argumento de las dos funciones. Este archivo no arma
// JSON a mano: solo lo envuelve, lo manda y traduce lo que vuelve.
//
// R-A1: vive en adapters/ porque toca el mundo. `package:http` es Dart puro, así
// que se testea en la VM con un MockClient, sin Supabase levantado. No usa el SDK
// de Supabase (§5.9).

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/model.dart';
import '../core/ports.dart';
import '../core/wire.dart';

/// `CS003`: el lote pasa los 500 jobs o el MB de `public.sync_push` (§6.1).
const kRpcLoteDemasiadoGrande = 'CS003';

/// Clasifica un error de PostgREST por su `code` y, si el código no está en la
/// tabla de §6.1, por el status.
///
/// PostgREST devuelve todo SQLSTATE propio de la base como `400`, así que el
/// status solo no alcanza: `CS002` (app vieja) y `400` comparten status y uno
/// es transitorio y el otro no.
///
/// - `CS001` (sobre mal formado) y `22023` (`jobs`, `entities`, `watermark` o
///   `limit` con otra forma): [FailureKind.payload].
/// - `CS002` (sin sobre o `schema_version` vieja): [FailureKind.transient]. Los
///   jobs esperan en `PENDING` a que se actualice la app, como el `426` del
///   BFF. La UI lo distingue de «sin red» por el `code`.
/// - `42501` (sin sesión): [FailureKind.transient], aunque venga con `403`. El
///   refresh del token es de la app (§10).
/// - `CS003` no se clasifica acá: [SupabaseRpcTransport.push] parte el lote y
///   no lo deja salir. Si llegara, es [FailureKind.payload] por su `400`.
FailureKind kindForRpcError(int status, String code) => switch (code) {
  'CS001' || '22023' => FailureKind.payload,
  'CS002' || '42501' => FailureKind.transient,
  _ => kindForStatus(status),
};

/// `SyncTransport` sobre las RPC de sync de Supabase (PostgREST).
class SupabaseRpcTransport implements SyncTransport {
  SupabaseRpcTransport({
    required Uri projectUrl,
    required this.anonKey,
    required this.token,
    required this.device,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _rpc = _conBarra(projectUrl).resolve('rest/v1/rpc/'),
       _client = client ?? http.Client();

  /// `https://<proyecto>.supabase.co/rest/v1/rpc/`.
  final Uri _rpc;

  /// La anon key del proyecto. Es pública: identifica al proyecto, no al
  /// colportor. Lo que da permisos es [token].
  final String anonKey;

  /// El sobre de §5.3. Es del transporte y no del lote: identifica a esta
  /// instalación, no a lo que sube.
  final ClientEnvelope device;

  /// El JWT vigente. El motor **no** gestiona la sesión (§10): la app le pasa
  /// una función y se encarga del refresh por su lado.
  final Future<String?> Function() token;

  final http.Client _client;
  final Duration timeout;

  /// Sube el lote. Si el servidor lo rechaza por grande (`CS003`), lo parte por
  /// la mitad y sube cada parte, en orden (§5.5), hasta que entre.
  ///
  /// Un solo job que igual pasa el tope vuelve como `invalid` con `code`
  /// `CS003`: partirlo no se puede, y descartarlo perdería una venta. Así queda
  /// visible en la cola de error y el resto del lote sigue.
  ///
  /// Si una parte falla por otra cosa, la falla sale entera aunque las partes
  /// anteriores hayan entrado: el motor devuelve el lote a `PENDING` y, al
  /// reintentarlo, lo que ya entró vuelve `duplicate` por su `client_op_id`.
  @override
  Future<PushResult> push(PushBatch batch) => _subir(batch.jobs);

  Future<PushResult> _subir(List<SyncJob> jobs) async {
    try {
      final cuerpo = await _llamar(
        'sync_push',
        pushRequestToJson(PushBatch(jobs), device),
      );
      return _leer<PushResult>(() => pushResponseFromJson(cuerpo));
    } on TransportFailure catch (falla) {
      if (falla.code != kRpcLoteDemasiadoGrande) rethrow;
      if (jobs.length == 1) {
        return PushResult(
          serverTime: DateTime.now().toUtc(),
          results: [
            JobResult(
              clientOpId: jobs.single.clientOpId,
              outcome: JobOutcome.invalid,
              code: falla.code,
              message: falla.message,
            ),
          ],
        );
      }
      final mitad = jobs.length ~/ 2;
      final primera = await _subir(jobs.sublist(0, mitad));
      final segunda = await _subir(jobs.sublist(mitad));
      return PushResult(
        serverTime: segunda.serverTime,
        results: [...primera.results, ...segunda.results],
      );
    }
  }

  @override
  Future<PullDelta> pull({
    required List<String> entities,
    String? watermark,
    int? limit,
  }) async {
    final cuerpo = await _llamar(
      'sync_pull',
      pullRequestToJson(
        device,
        entities: entities,
        watermark: watermark,
        limit: limit,
      ),
    );
    return _leer<PullDelta>(
      () => pullResponseFromJson(cuerpo, watermarkPrevio: watermark),
    );
  }

  void close() => _client.close();

  // --- traducción -------------------------------------------------------------

  /// `POST /rest/v1/rpc/<funcion>` con `{"p_body": cuerpo}`. Devuelve el cuerpo
  /// de la respuesta, o lanza [TransportFailure].
  ///
  /// Ninguna excepción de `package:http` escapa de acá: el núcleo no sabría
  /// clasificarla, y clasificar es lo que decide entre `PENDING` e `INVALID`.
  Future<Map<String, Object?>> _llamar(
    String funcion,
    Map<String, Object?> cuerpo,
  ) async {
    final http.Response respuesta;
    try {
      respuesta = await _client
          .post(
            _rpc.resolve(funcion),
            headers: await _headers(),
            body: jsonEncode({'p_body': cuerpo}),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const TransportFailure(
        FailureKind.transient,
        code: 'TIMEOUT',
        message: 'Supabase no respondió a tiempo',
      );
    } on http.ClientException catch (e) {
      throw TransportFailure(
        FailureKind.transient,
        code: 'SIN_RED',
        message: e.message,
      );
    }

    if (respuesta.statusCode >= 300) throw _falla(respuesta);

    final Object? json;
    try {
      json = jsonDecode(utf8.decode(respuesta.bodyBytes));
    } on FormatException {
      throw _ilegible;
    }
    if (json is! Map) throw _ilegible;
    return json.cast<String, Object?>();
  }

  /// Un cuerpo ilegible es un bug del servidor. Mandar a `INVALID` un job que
  /// estaba bien porque la respuesta vino rota sería peor que reintentarlo.
  static const _ilegible = TransportFailure(
    FailureKind.transient,
    code: 'RESPUESTA_ILEGIBLE',
    message: 'Supabase respondió algo que no es el JSON acordado',
  );

  /// Decodifica con el codec. Un 200 con otra forma (un `watermark` que no es
  /// string, `rows` que no es objeto) es [_ilegible], no un `TypeError` suelto.
  static T _leer<T>(T Function() decodificar) {
    try {
      return decodificar();
    } on FormatException {
      throw _ilegible;
    } on TypeError {
      throw _ilegible;
    }
  }

  Future<Map<String, String>> _headers() async {
    final jwt = await token();
    return {
      'apikey': anonKey,
      if (jwt != null) 'Authorization': 'Bearer $jwt',
      'Accept': 'application/json',
      'Content-Type': 'application/json; charset=utf-8',
    };
  }

  /// El error de PostgREST: `{"code", "message", "details", "hint"}`, con el
  /// SQLSTATE en `code`.
  TransportFailure _falla(http.Response r) {
    var codigo = 'HTTP_${r.statusCode}';
    var mensaje = '';
    try {
      final cuerpo = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
      codigo = (cuerpo['code'] as String?) ?? codigo;
      mensaje = (cuerpo['message'] as String?) ?? '';
    } on Object {
      // Un error sin cuerpo JSON (un 502 del gateway) sigue siendo un error: el
      // status alcanza.
    }

    return TransportFailure(
      kindForRpcError(r.statusCode, codigo),
      status: r.statusCode,
      code: codigo,
      message: mensaje,
      retryAfter: _retryAfter(r.headers['retry-after']),
    );
  }

  /// `Retry-After` en segundos, el que manda el gateway de Supabase con el 429.
  static Duration? _retryAfter(String? valor) {
    if (valor == null) return null;
    final segundos = int.tryParse(valor.trim());
    return segundos == null ? null : Duration(seconds: segundos);
  }

  /// `resolve` reemplaza el último segmento de un path sin barra final: con
  /// `https://x.supabase.co/base` se perdería `base`.
  static Uri _conBarra(Uri u) =>
      u.path.endsWith('/') ? u : u.replace(path: '${u.path}/');
}
