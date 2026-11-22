import 'dart:convert';

import '../core/backup.dart';
import '../core/ports.dart';

/// El `appDataFolder` de Drive, en memoria.
class FakeArchive implements ArchivePort {
  FakeArchive({
    bool authorized = false,
    DateTime Function()? clock,
    String Function(List<int>)? digest,
    this.informaHashRemoto = false,
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

  /// Como Drive: `list()` trae el hash que el archivo calculó sobre lo que
  /// guardó (`BackupEntry.storedHash`), así que la integridad se verifica sin
  /// bajar nada. Apagado, el archivo no lo informa y `verifyChain` baja el blob.
  final bool informaHashRemoto;

  final Map<String, List<int>> _payloads = {};
  final List<BackupEntry> entries = [];

  /// Cuántas veces se bajó un blob: la verificación por metadatos no baja nada.
  int descargas = 0;

  /// Si la próxima subida (o la que sigue) se corta: no queda nada en el
  /// archivo, como una subida de Drive que no terminó.
  int subidasQueFallan = 0;

  /// Los ids que se borraron, en orden.
  final List<String> borrados = [];

  /// Si borrar explota (Drive sin red a mitad de la poda).
  bool failOnDelete = false;

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
  Future<List<BackupEntry>> list() async => [
        for (final e in entries)
          if (informaHashRemoto && _payloads.containsKey(e.id))
            BackupEntry(
              id: e.id,
              createdAt: e.createdAt,
              contentHash: e.contentHash,
              watermark: e.watermark,
              parentId: e.parentId,
              bytes: e.bytes,
              exportedAt: e.exportedAt,
              storedHash: _digest(_payloads[e.id]!),
              keyId: e.keyId,
              firma: e.firma,
            )
          else
            e,
      ];

  int _secuencia = 0;
  DateTime? _ultimaFecha;

  @override
  Future<BackupEntry> upload({
    required List<int> payload,
    required String? parentId,
    required String watermark,
    DateTime? exportedAt,
    String? keyId,
    String? firma,
  }) async {
    if (subidasQueFallan > 0) {
      subidasQueFallan--;
      throw StateError('la subida se cortó');
    }
    final id = 'backup-${++_secuencia}';
    // Drive no repite el instante de dos subidas: la base más nueva se
    // reconoce por su fecha.
    var ahora = _clock();
    final ultima = _ultimaFecha;
    if (ultima != null && !ahora.isAfter(ultima)) {
      ahora = ultima.add(const Duration(milliseconds: 1));
    }
    _ultimaFecha = ahora;
    final entrada = BackupEntry(
      id: id,
      createdAt: ahora,
      contentHash: _digest(payload),
      watermark: watermark,
      parentId: parentId,
      bytes: payload.length,
      exportedAt: exportedAt,
      keyId: keyId,
      firma: firma,
    );
    _payloads[id] = payload;
    entries.add(entrada);
    return entrada;
  }

  @override
  Future<List<int>> download(String id) async {
    descargas++;
    return _payloads[id] ?? (throw StateError('no existe $id en el archivo'));
  }

  @override
  Future<void> delete(String id) async {
    if (failOnDelete) throw StateError('no se pudo borrar');
    borrados.add(id);
    deleteEntry(id);
  }
}

/// Cifrado de mentira: invierte los bytes.
///
/// No prueba nada criptográfico —eso es del adaptador y del crypto nativo del
/// OS—, pero sí lo que le importa al núcleo: que lo que sale al archivo no sea
/// el texto en claro, y que descifrar sea la inversa exacta de cifrar.
class FakeCrypto implements CryptoPort {
  FakeCrypto({this.llave = 'llave-1'});

  /// De qué llave es este cifrado: dos `FakeCrypto` con la misma [llave] son la
  /// misma persona (la DEK recuperada en otro teléfono); con otra, un teléfono
  /// nuevo con su propia DEK.
  final String llave;

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

  @override
  Future<String> keyId() async => 'id-$llave';

  /// Firma de mentira pero que depende de la [llave] y del mensaje: dos
  /// `FakeCrypto` con la misma llave firman igual, con otra no.
  @override
  Future<String> sign(String mensaje) async => 'f-$llave-${hashOf(utf8.encode(mensaje))}';

  @override
  Future<bool> verifySignature(String mensaje, String? firma) async =>
      firma != null && firma == await sign(mensaje);

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

  /// Las cadenas que recibió el último restore, de la base a la punta.
  List<List<List<int>>> chainsRestored = [];

  @override
  Future<void> restore(List<List<int>> payloadsInOrder) =>
      restoreChains([payloadsInOrder]);

  @override
  Future<void> restoreChains(List<List<List<int>>> chains) async {
    if (failOnRestore) throw StateError('el restore falló');

    // Base primero, después cada incremental encima: el orden es la cadena.
    // Con varias cadenas, las claves se suman (la última pisa a la anterior).
    final acumulado = <String, Object?>{};
    for (final cadena in chains) {
      for (final payload in cadena) {
        acumulado
            .addAll(jsonDecode(utf8.decode(payload)) as Map<String, Object?>);
      }
    }
    chainsRestored = [for (final c in chains) [for (final p in c) List.of(p)]];
    restored = acumulado;
    onRestore?.call(acumulado);
  }
}

/// Los envoltorios de la clave (ADR-006) que viajan con el respaldo, en
/// memoria. En Drive viven en el mismo `appDataFolder` que la cadena; acá van
/// aparte porque son otro puerto.
class FakeKeyEnvelopes implements KeyEnvelopePort {
  /// Por llave, lo último que se subió.
  final Map<String, List<int>> guardados = {};

  /// Cuántas veces se subió uno.
  int subidas = 0;

  /// Si subir explota (Drive sin red).
  bool failOnPut = false;

  @override
  Future<void> putEnvelope(String keyId, List<int> bytes) async {
    if (failOnPut) throw StateError('Drive no contestó');
    subidas++;
    guardados[keyId] = List.of(bytes);
  }

  @override
  Future<List<int>?> getEnvelope(String keyId) async => guardados[keyId];

  @override
  Future<Set<String>> envelopeKeyIds() async => guardados.keys.toSet();
}
