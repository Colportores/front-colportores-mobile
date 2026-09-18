import 'dart:async';

import 'backup.dart';
import 'ports.dart';

/// Backup incremental cifrado E2E contra el `appDataFolder` (ADR-003, §5.7).
///
/// Todo lo que sale a la red pasa por [CryptoPort.encrypt] primero. El motor no
/// elige el algoritmo ni toca la clave: eso es del adaptador.
class BackupService {
  BackupService({
    required ArchivePort archive,
    required CryptoPort crypto,
    required SnapshotPort snapshot,
    DateTime Function()? clock,
  })  : _archive = archive,
        _crypto = crypto,
        _snapshot = snapshot,
        _clock = clock ?? (() => DateTime.now().toUtc());

  final ArchivePort _archive;
  final CryptoPort _crypto;
  final SnapshotPort _snapshot;
  final DateTime Function() _clock;

  /// OAuth con Google Drive (HU-SYNC-004).
  Future<bool> authorize() => _archive.authorize();

  Future<bool> get isAuthorized => _archive.isAuthorized;

  /// Un backup incremental, o el completo si todavía no hay cadena
  /// (HU-SYNC-005).
  ///
  /// [watermark] queda guardado en la entrada: es de donde arranca la
  /// reconciliación de §7 fase 3.
  Future<BackupEntry> backupNow({required String watermark}) {
    // Uno por vez. Dos backups en paralelo leen la misma punta y suben los dos
    // con el mismo padre: eso es un fork, y un fork deja la cadena entera
    // inservible porque no hay forma de saber cuál rama es la buena. Pasa solo
    // con que el colportor toque "hacer backup" mientras corre el del cierre de
    // jornada.
    return _enCurso = _serializado(_enCurso, () => _backupNow(watermark));
  }

  Future<BackupEntry> _backupNow(String watermark) async {
    final cadena = buildChain(await _archive.list());

    // Una cadena rota no se extiende: agregarle un eslabón encima haría que el
    // restore falle igual, pero más tarde y con más datos adentro.
    final punta = cadena.ok ? cadena.tip : null;

    final crudo = await _snapshot.export(since: punta?.createdAt);
    final cifrado = await _crypto.encrypt(crudo);

    return _archive.upload(
      payload: cifrado,
      parentId: punta?.id,
      watermark: watermark,
    );
  }

  /// Integridad de la cadena (HU-SYNC-009).
  ///
  /// Verifica los enlaces **y** los hashes: una entrada que existe pero está
  /// corrupta rompe el restore igual que una que falta, y solo se nota bajando
  /// el archivo.
  Future<ChainStatus> verifyChain({bool checkContent = true}) async {
    final cadena = buildChain(await _archive.list());
    if (!cadena.ok || !checkContent) return cadena;

    for (final entrada in cadena.ordered) {
      final bytes = await _archive.download(entrada.id);
      if (_crypto.digest(bytes) != entrada.contentHash) {
        return ChainStatus(
            problems: const {ChainProblem.brokenLink}, ordered: const []);
      }
    }
    return cadena;
  }

  /// Reconstruye la DB desde la cadena (HU-SYNC-006).
  ///
  /// Devuelve la entrada de la punta —de cuándo son los datos— o `null` si no
  /// había nada usable.
  Future<BackupEntry?> restore() => _serializado(_enCurso, _restore);

  Future<BackupEntry?> _restore() async {
    final cadena = await verifyChain();
    if (!cadena.ok) return null;

    final payloads = <List<int>>[];
    for (final entrada in cadena.ordered) {
      payloads.add(await _crypto.decrypt(await _archive.download(entrada.id)));
    }

    // El SnapshotPort arma un archivo temporal y recién al final reemplaza la
    // DB en uso: si esto falla a la mitad, la DB anterior sigue entera.
    await _snapshot.restore(payloads);
    return cadena.tip;
  }

  DateTime get now => _clock();

  Future<BackupEntry>? _enCurso;

  /// Encadena [trabajo] después de [anterior], pase lo que pase con ella.
  Future<T> _serializado<T>(
      Future<void>? anterior, Future<T> Function() trabajo) async {
    if (anterior != null) {
      // Si la anterior falló, no es asunto de esta: solo hay que esperarla.
      await anterior.then<void>((_) {}, onError: (Object _) {});
    }
    return trabajo();
  }
}
