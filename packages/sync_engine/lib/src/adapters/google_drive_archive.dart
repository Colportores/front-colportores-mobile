// El `appDataFolder` de Google Drive de verdad (ADR-006, §6: va directo, sin BFF).
//
// `DriveArchive` habla con el `drive-mock` del prototipo, que no tiene la forma de
// la API real. Este es el que corre en el teléfono: Drive v3 sobre HTTP, con
// `package:http` (Dart puro, así que se prueba en la VM con un `MockClient`).
//
// Lo que la cadena necesita de Drive:
// - **Carpeta oculta de la app**: `spaces=appDataFolder` y `parents: [appDataFolder]`,
//   con el scope `drive.appdata`. Ni se ve en el Drive de la persona ni la puede
//   leer otra app.
// - **Subida atómica**: una sola petición `multipart` con metadatos y bytes. Si se
//   corta, Drive no crea el archivo: no queda una entrada a medias, y eso es lo que
//   hace que el backup «cuente» recién cuando terminó (HU-SYNC-005).
// - **Los metadatos de la cadena en `appProperties`**, no en el nombre: el nombre
//   no lo indexa nadie y un renombre rompería la cadena. El watermark va en
//   `description`, porque `appProperties` limita cada par a 124 bytes y el
//   watermark es un string opaco del servidor.
// - **El hash que calculó Drive**: `sha256Checksum` viene en el listado y es el de
//   lo que Drive guardó. Compararlo con el que calculó el teléfono antes de subir
//   verifica la cadena sin bajar un solo blob (HU-SYNC-009).
//
// El OAuth queda afuera, como en `DriveArchive`: la app le pasa [token] y este
// archivo no depende de `google_sign_in`.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/backup.dart';
import '../core/ports.dart';
import 'drive_archive.dart';

/// No hay un token para pedirle nada a Drive: Google no lo dio (la persona quitó
/// el permiso, o no hay red para renovarlo). No se llegó a hablar con Drive, así
/// que no es lo mismo que [ArchiveUnauthorized]: quien da el token ya sabe si el
/// permiso se perdió, y un corte de red no debe pasar por una revocación.
class ArchiveSinToken extends ArchiveFailure {
  const ArchiveSinToken(super.message, [super.detail]);
}

/// Drive contestó 401 o 403: el token venció o la persona le quitó el permiso a
/// la app desde su cuenta de Google (HU-SYNC-004, «Edge»). La app marca el
/// respaldo como «Reconectar».
class ArchiveUnauthorized extends ArchiveFailure {
  const ArchiveUnauthorized(super.message, [super.detail]);
}

/// El Drive de la persona no tiene espacio: el respaldo no se guardó (vista 16D·10).
class ArchiveNoSpace extends ArchiveFailure {
  const ArchiveNoSpace(super.message, [super.detail]);
}

/// `ArchivePort` sobre la API REST de Google Drive v3, en el `appDataFolder`.
class GoogleDriveArchive implements ArchivePort {
  GoogleDriveArchive({
    required this.token,
    required this.digest,
    Uri? apiUrl,
    Uri? uploadUrl,
    http.Client? client,
    this.timeout = const Duration(minutes: 2),
  })  : _api = apiUrl ?? Uri.parse('https://www.googleapis.com/drive/v3/'),
        _upload = uploadUrl ??
            Uri.parse('https://www.googleapis.com/upload/drive/v3/files'),
        _client = client ?? http.Client();

  final Uri _api;
  final Uri _upload;

  /// El token de acceso vigente, o `null` si no hay cuenta conectada o Google ya
  /// no da el permiso.
  final Future<String?> Function() token;

  /// Cómo se calcula el `contentHash`: SHA-256 en hexadecimal, en minúsculas, el
  /// mismo formato que el `sha256Checksum` de Drive. **Tiene que ser el mismo**
  /// que el del `CryptoPort` en juego.
  final String Function(List<int>) digest;

  final http.Client _client;
  final Duration timeout;

  /// Los campos que se piden de cada archivo: lo mínimo para armar la cadena.
  static const _campos = 'id,createdTime,size,sha256Checksum,description,appProperties';

  @override
  Future<bool> authorize() async => (await token()) != null;

  @override
  Future<bool> get isAuthorized async => (await token()) != null;

  @override
  Future<List<BackupEntry>> list() async {
    final entradas = <BackupEntry>[];
    String? pagina;
    do {
      final uri = _api.resolve('files').replace(queryParameters: {
        'spaces': 'appDataFolder',
        'pageSize': '1000',
        'fields': 'nextPageToken,files($_campos)',
        'orderBy': 'createdTime',
        if (pagina != null) 'pageToken': pagina,
      });
      final resp = await _pedir((h) => _client.get(uri, headers: h));
      final cuerpo = _json(resp);
      for (final a in ((cuerpo['files'] as List?) ?? const []).cast<Map<String, Object?>>()) {
        if (_entrada(a) case final e?) entradas.add(e);
      }
      pagina = cuerpo['nextPageToken'] as String?;
    } while (pagina != null);
    return entradas;
  }

  @override
  Future<BackupEntry> upload({
    required List<int> payload,
    required String? parentId,
    required String watermark,
    DateTime? exportedAt,
    String? keyId,
  }) async {
    // El hash se calcula acá, sobre lo que se va a subir. Que lo calcule el
    // teléfono y que Drive calcule el suyo aparte es lo que hace que comparar los
    // dos diga algo: si Drive guardó otra cosa, no coinciden.
    final hash = digest(payload);

    final metadatos = jsonEncode({
      'name': 'backup',
      'parents': ['appDataFolder'],
      'description': watermark,
      'appProperties': {
        // Cadena vacía y no ausente: así «es la base» se distingue de «el
        // metadato se perdió».
        'parent_id': parentId ?? '',
        'content_hash': hash,
        if (exportedAt != null) 'exported_at': exportedAt.toUtc().toIso8601String(),
        if (keyId != null) 'key_id': keyId,
      },
    });

    // Un separador distinto en cada pedido: lo que se sube es ruido cifrado, y si
    // el separador apareciera adentro Drive cortaría el archivo ahí.
    final azar = Random.secure();
    final limite = 'colportores-${[
      for (var i = 0; i < 16; i++) azar.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join()}';
    final cuerpo = BytesBuilder(copy: false)
      ..add(utf8.encode('--$limite\r\n'
          'Content-Type: application/json; charset=UTF-8\r\n\r\n'
          '$metadatos\r\n'
          '--$limite\r\n'
          'Content-Type: application/octet-stream\r\n\r\n'))
      ..add(payload)
      ..add(utf8.encode('\r\n--$limite--'));

    final uri = _upload.replace(queryParameters: {
      'uploadType': 'multipart',
      'fields': _campos,
    });
    final resp = await _pedir((h) => _client.post(
          uri,
          headers: {...h, 'Content-Type': 'multipart/related; boundary=$limite'},
          body: cuerpo.takeBytes(),
        ));

    final entrada = _entrada(_json(resp));
    if (entrada == null) {
      throw const ArchiveFailure('la subida no devolvió los metadatos de la cadena');
    }
    return entrada;
  }

  @override
  Future<List<int>> download(String id) async {
    final uri = _api.resolve('files/${Uri.encodeComponent(id)}')
        .replace(queryParameters: {'alt': 'media'});
    final resp = await _pedir((h) => _client.get(uri, headers: h));
    return resp.bodyBytes;
  }

  @override
  Future<void> delete(String id) async {
    final uri = _api.resolve('files/${Uri.encodeComponent(id)}');
    // 404: ya no está, que es lo que se quería.
    await _pedir((h) => _client.delete(uri, headers: h), toleradas: {404});
  }

  /// Un archivo del listado como entrada de la cadena.
  ///
  /// Devuelve `null` si le faltan los metadatos: un archivo suelto en el
  /// `appDataFolder` —subido por una versión vieja, o el del envoltorio de la
  /// clave— no es un eslabón, y meterlo en la cadena la haría dar rota para
  /// siempre.
  BackupEntry? _entrada(Map<String, Object?> a) {
    final props = (a['appProperties'] as Map?)?.cast<String, Object?>();
    if (props == null) return null;

    final hash = props['content_hash'] as String?;
    final watermark = a['description'] as String?;
    if (hash == null || watermark == null) return null;

    final padre = props['parent_id'] as String?;
    final creado = DateTime.tryParse('${a['createdTime']}')?.toUtc();
    if (creado == null) return null;
    return BackupEntry(
      id: '${a['id']}',
      createdAt: creado,
      contentHash: hash,
      watermark: watermark,
      parentId: (padre == null || padre.isEmpty) ? null : padre,
      bytes: int.tryParse('${a['size']}') ?? 0,
      exportedAt: DateTime.tryParse('${props['exported_at']}')?.toUtc(),
      storedHash: (a['sha256Checksum'] as String?)?.toLowerCase(),
      keyId: props['key_id'] as String?,
    );
  }

  Future<http.Response> _pedir(
    Future<http.Response> Function(Map<String, String> headers) hacer, {
    Set<int> toleradas = const {},
  }) async {
    final t = await token();
    if (t == null) {
      throw const ArchiveSinToken('no hay un token de Drive vigente');
    }
    final resp = await hacer({'Authorization': 'Bearer $t'}).timeout(timeout);
    if (resp.statusCode >= 200 && resp.statusCode < 300) return resp;
    if (toleradas.contains(resp.statusCode)) return resp;
    throw _falla(resp);
  }

  /// La falla de Drive, con la clase que le dice a la app qué hacer.
  ArchiveFailure _falla(http.Response resp) {
    final motivo = _motivo(resp);
    // Sin el cuerpo en el mensaje: puede traer el nombre de la cuenta.
    final mensaje = 'Drive respondió ${resp.statusCode}'
        '${motivo.isEmpty ? '' : ' ($motivo)'}';
    if (resp.statusCode == 401) return ArchiveUnauthorized(mensaje);
    if (resp.statusCode == 403) {
      if (motivo == 'storageQuotaExceeded') return ArchiveNoSpace(mensaje);
      // Un 403 por límite de pedidos pasa solo; el resto es un permiso que falta.
      if (motivo == 'rateLimitExceeded' ||
          motivo == 'userRateLimitExceeded' ||
          motivo == 'backendError') {
        return ArchiveFailure(mensaje);
      }
      return ArchiveUnauthorized(mensaje);
    }
    return ArchiveFailure(mensaje);
  }

  String _motivo(http.Response resp) {
    try {
      final cuerpo = jsonDecode(resp.body);
      final errores = ((cuerpo as Map)['error'] as Map?)?['errors'] as List?;
      return '${(errores?.first as Map?)?['reason'] ?? ''}';
    } on Object {
      return '';
    }
  }

  Map<String, Object?> _json(http.Response resp) {
    try {
      return jsonDecode(resp.body) as Map<String, Object?>;
    } on Object {
      throw ArchiveFailure('Drive respondió algo que no es JSON (${resp.statusCode})');
    }
  }
}
