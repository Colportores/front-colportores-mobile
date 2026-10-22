import 'dart:convert';

import '../core/backup.dart';
import '../core/ports.dart';

/// El `appDataFolder` de Drive, en memoria.
class FakeArchive implements ArchivePort {
  FakeArchive({
    bool authorized = false,
    DateTime Function()? clock,
    String Function(List<int>)? digest,
  })  : _authorized = authorized,
        _clock = clock ?? (() => DateTime.now().toUtc()),
        _digest = digest ?? FakeCrypto.hashOf;

  final DateTime Function() _clock;

  /// Cómo se calcula el `contentHash`. Tiene que ser **el mismo** que usa el
  /// `CryptoPort` en juego: si no, `verifyChain()` compara un hash contra otro
  /// y da cadena rota siempre. Un adaptador de Drive real tiene el mismo
  /// problema, así que conviene que el fake lo tenga también.
  final String Function(List<int>) _digest;
  bool _authorized;

  final Map<String, List<int>> _payloads = {};
  final List<BackupEntry> entries = [];

  /// El usuario nunca autorizó Drive. Es el caso de §7 "sin backup".
  void revoke() => _authorized = false;

  /// Rompe un eslabón, para probar `verifyChain()`.
  void corrupt(String id) => _payloads[id] = utf8.encode('basura');

  void deleteEntry(String id) {
    entries.removeWhere((e) => e.id == id);
    _payloads.remove(id);
  }

  @override
  Future<bool> authorize() async => _authorized = true;

  @override
  Future<bool> get isAuthorized async => _authorized;

  @override
  Future<List<BackupEntry>> list() async => List.of(entries);

  @override
  Future<BackupEntry> upload({
    required List<int> payload,
    required String? parentId,
    required String watermark,
  }) async {
    final id = 'backup-${entries.length + 1}';
    final entrada = BackupEntry(
      id: id,
      createdAt: _clock(),
      contentHash: _digest(payload),
      watermark: watermark,
      parentId: parentId,
      bytes: payload.length,
    );
    _payloads[id] = payload;
    entries.add(entrada);
    return entrada;
  }

  @override
  Future<List<int>> download(String id) async =>
      _payloads[id] ?? (throw StateError('no existe $id en el archivo'));
}

/// Cifrado de mentira: invierte los bytes.
///
/// No prueba nada criptográfico —eso es del adaptador y del crypto nativo del
/// OS—, pero sí lo que le importa al núcleo: que lo que sale al archivo no sea
/// el texto en claro, y que descifrar sea la inversa exacta de cifrar.
class FakeCrypto implements CryptoPort {
  /// Lo que el fake escribió, en claro, para que el test pueda mirarlo.
  final List<List<int>> encrypted = [];

  @override
  Future<List<int>> encrypt(List<int> plaintext) async {
    encrypted.add(plaintext);
    return plaintext.reversed.toList();
  }

  @override
  Future<List<int>> decrypt(List<int> ciphertext) async =>
      ciphertext.reversed.toList();

  @override
  String digest(List<int> bytes) => hashOf(bytes);

  /// Hash barato pero estable: alcanza para detectar un payload cambiado.
  static String hashOf(List<int> bytes) {
    var h = 17;
    for (final b in bytes) {
      h = (h * 31 + b) & 0x7fffffff;
    }
    return 'h$h';
  }
}

/// La DB local vista como archivo.
///
/// El "contenido" es JSON: el estado de las tablas más `sync_queue`, que es lo
/// que §7 exige que el backup incluya.
class FakeSnapshot implements SnapshotPort {
  FakeSnapshot({this.onRestore});

  /// Lo que el motor considera el estado local al momento de exportar.
  Map<String, Object?> state = {};

  /// Se llama con el estado reconstruido. La app real repuebla Drift acá; el
  /// test lo usa para devolver los jobs de `sync_queue` a la cola.
  final void Function(Map<String, Object?> restaurado)? onRestore;

  final List<DateTime?> exports = [];
  Map<String, Object?>? restored;

  /// Si el restore explota a la mitad. La DB anterior tiene que quedar entera.
  bool failOnRestore = false;

  @override
  Future<List<int>> export({DateTime? since}) async {
    exports.add(since);
    return utf8
        .encode(jsonEncode({'since': since?.toIso8601String(), ...state}));
  }

  @override
  Future<void> restore(List<List<int>> payloadsInOrder) async {
    if (failOnRestore) throw StateError('el restore falló');

    // Base primero, después cada incremental encima: el orden es la cadena.
    final acumulado = <String, Object?>{};
    for (final payload in payloadsInOrder) {
      acumulado
          .addAll(jsonDecode(utf8.decode(payload)) as Map<String, Object?>);
    }
    restored = acumulado;
    onRestore?.call(acumulado);
  }
}
