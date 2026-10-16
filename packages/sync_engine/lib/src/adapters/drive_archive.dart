// El `appDataFolder` de Drive sobre HTTP (ADR-003, §6: va directo, sin BFF).
//
// R-A1: vive en adapters/ porque toca el mundo. `package:http` es Dart puro, así
// que se testea en la VM contra el `drive-mock` sin emulador ni dispositivo.
//
// La API de Drive y la del mock coinciden en lo que acá importa: subir bytes con
// metadatos arbitrarios, listarlos y bajarlos. Los metadatos de la cadena
// —padre, watermark y hash— van en `appProperties` y **no en el nombre del
// archivo**: el nombre no lo indexa nadie y un rename rompería la cadena entera.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/backup.dart';
import '../core/ports.dart';

/// `ArchivePort` sobre HTTP.
///
/// Contra el `drive-mock` en desarrollo; contra Drive en producción, cambiando
/// [baseUrl]. El OAuth queda afuera a propósito: la app le pasa [token], igual
/// que a `BffTransport`, y así este archivo no depende de `google_sign_in` y se
/// puede probar sin una cuenta de Google.
class DriveArchive implements ArchivePort {
  DriveArchive({
    required Uri baseUrl,
    required this.token,
    required this.digest,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
  })  : _base = baseUrl,
        _client = client ?? http.Client();

  final Uri _base;

  /// El token de acceso vigente, o `null` si el usuario no autorizó Drive.
  final Future<String?> Function() token;

  /// Cómo se calcula el `contentHash`. **Tiene que ser el mismo** que usa el
  /// `CryptoPort` en juego: si no, `verifyChain()` compara un hash contra otro
  /// y da cadena rota siempre, aunque esté sana.
  final String Function(List<int>) digest;

  final http.Client _client;
  final Duration timeout;

  @override
  Future<bool> authorize() async => (await token()) != null;

  @override
  Future<bool> get isAuthorized async => (await token()) != null;

  @override
  Future<List<BackupEntry>> list() async {
    final cuerpo = await _json(() async =>
        _client.get(_base.resolve('files'), headers: await _headers()));

    final archivos = (cuerpo['archivos'] as List?) ?? const [];
    return [
      for (final a in archivos.cast<Map<String, Object?>>())
        if (_entrada(a) case final e?) e,
    ];
  }

  @override
  Future<BackupEntry> upload({
    required List<int> payload,
    required String? parentId,
    required String watermark,
  }) async {
    // El hash se calcula acá, sobre lo que se va a subir, y viaja como
    // metadato. Que lo calcule el cliente y no el servidor es lo que hace que
    // `verifyChain()` sirva de algo: si Drive devuelve bytes distintos de los
    // que se subieron, el hash guardado no coincide con el de lo que bajó.
    final hash = digest(payload);

    final req = http.MultipartRequest('POST', _base.resolve('files'))
      ..headers.addAll(await _headers())
      ..fields['app_properties'] = jsonEncode({
        // Cadena vacía y no ausente: el mock y Drive guardan strings, y así
        // "es la base" se distingue de "el metadato se perdió".
        'parent_id': parentId ?? '',
        'watermark': watermark,
        'content_hash': hash,
      })
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        payload,
        filename: 'backup.bin',
      ));

    final resp = await http.Response.fromStream(
        await _client.send(req).timeout(timeout));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ArchiveFailure('subida rechazada (${resp.statusCode})', resp.body);
    }

    final cuerpo = jsonDecode(resp.body) as Map<String, Object?>;
    final entrada = _entrada(cuerpo);
    if (entrada == null) {
      throw ArchiveFailure(
          'la subida no devolvió los metadatos de la cadena', resp.body);
    }
    return entrada;
  }

  @override
  Future<List<int>> download(String id) async {
    final resp = await _client
        .get(_base.resolve('files/$id'), headers: await _headers())
        .timeout(timeout);
    if (resp.statusCode != 200) {
      throw ArchiveFailure('no se pudo bajar $id (${resp.statusCode})', resp.body);
    }
    return resp.bodyBytes;
  }

  /// Borra una entrada. Fuera del puerto: lo usa la poda de cadenas viejas y la
  /// limpieza de los tests.
  Future<void> delete(String id) async {
    final resp = await _client
        .delete(_base.resolve('files/$id'), headers: await _headers())
        .timeout(timeout);
    if (resp.statusCode != 204 && resp.statusCode != 404) {
      throw ArchiveFailure('no se pudo borrar $id (${resp.statusCode})', resp.body);
    }
  }

  /// Un archivo del listado como entrada de la cadena.
  ///
  /// Devuelve `null` si le faltan los metadatos: un archivo suelto en el
  /// `appDataFolder` —subido por una versión vieja, o a medio subir— no es un
  /// eslabón, y meterlo en la cadena la haría dar rota para siempre.
  BackupEntry? _entrada(Map<String, Object?> a) {
    final props = (a['app_properties'] as Map?)?.cast<String, Object?>();
    if (props == null) return null;

    final hash = props['content_hash'] as String?;
    final watermark = props['watermark'] as String?;
    if (hash == null || watermark == null) return null;

    final padre = props['parent_id'] as String?;
    return BackupEntry(
      id: '${a['id']}',
      createdAt:
          DateTime.tryParse('${a['created_at']}')?.toUtc() ?? DateTime.now().toUtc(),
      contentHash: hash,
      watermark: watermark,
      parentId: (padre == null || padre.isEmpty) ? null : padre,
      bytes: (a['bytes'] as num?)?.toInt() ?? 0,
    );
  }

  Future<Map<String, String>> _headers() async {
    final t = await token();
    return {if (t != null) 'Authorization': 'Bearer $t'};
  }

  Future<Map<String, Object?>> _json(
      Future<http.Response> Function() pedir) async {
    final resp = await pedir().timeout(timeout);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ArchiveFailure('el archivo respondió ${resp.statusCode}', resp.body);
    }
    return jsonDecode(resp.body) as Map<String, Object?>;
  }
}

/// Algo salió mal contra el archivo remoto.
class ArchiveFailure implements Exception {
  const ArchiveFailure(this.message, [this.detail = '']);
  final String message;
  final String detail;

  @override
  String toString() =>
      'ArchiveFailure: $message${detail.isEmpty ? '' : ' — $detail'}';
}
