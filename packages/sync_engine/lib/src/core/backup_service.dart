import 'dart:async';

import 'backup.dart';
import 'ports.dart';

/// Cuándo la cadena de backups tiene que arrancar de una base nueva
/// (HU-SYNC-005, «Rotación de base»; ADR-006 §Algoritmo).
///
/// Una cadena larga hace el restore más lento y más frágil (un eslabón roto
/// corta todo lo que viene después), y una base vieja arrastra filas que ya no
/// existen. Por eso cada 30 días o 30 incrementales se sube una base completa.
class BackupPolicy {
  const BackupPolicy({
    this.maxBaseAge = const Duration(days: 30),
    this.maxPatches = 30,
  });

  /// Cuánto puede tener la base antes de reemplazarla.
  final Duration maxBaseAge;

  /// Cuántos incrementales puede tener encima antes de reemplazar la base.
  final int maxPatches;
}

/// Lo que dejó una verificación de integridad (HU-SYNC-009).
class IntegrityReport {
  const IntegrityReport({
    required this.status,
    required this.checkedAt,
    required this.hasBackup,
    required this.entries,
  });

  /// La cadena tal como la vio la verificación.
  final ChainStatus status;

  /// Cuándo se verificó, con el reloj del teléfono.
  final DateTime checkedAt;

  /// Había algo en Drive. Sin backups no hay cadena que verificar: no es un
  /// problema de integridad, es «todavía no hubo respaldo».
  final bool hasBackup;

  /// Cuántas entradas se miraron.
  final int entries;

  /// La cadena sirve entera (o no hay nada que verificar).
  bool get ok => !hasBackup || status.ok;

  /// Hay un problema real: el próximo backup parte de una base nueva.
  bool get needsRebase => hasBackup && !status.ok;

  /// Los problemas, por nombre, para el registro de auditoría. Sin contenido.
  Set<String> get problems => {for (final p in status.problems) p.name};
}

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
    this.policy = const BackupPolicy(),
  })  : _archive = archive,
        _crypto = crypto,
        _snapshot = snapshot,
        _clock = clock ?? (() => DateTime.now().toUtc());

  final ArchivePort _archive;
  final CryptoPort _crypto;
  final SnapshotPort _snapshot;
  final DateTime Function() _clock;

  /// Cuándo rota la base.
  final BackupPolicy policy;

  /// Se llama cuando un backup terminó de subir. El motor lo usa para que
  /// `SyncStatus.lastBackupAt` diga la verdad (HU-SYNC-007).
  ///
  /// Si lanza, el backup **no** se da por fallido: ya está en Drive, y un
  /// contador de pantalla no puede deshacerlo.
  Future<void> Function(BackupEntry entrada)? alTerminarUnBackup;

  /// El watermark de pull de la DB, para guardarlo en el backup (§7, fase 3).
  /// Lo pone el motor: la app llama a `backupNow()` sin saber qué es un
  /// watermark.
  Future<String?> Function()? watermarkProvider;

  /// Se llama con el resultado de cada [verifyIntegrity]. La app lo usa para
  /// anotar el resultado en el `audit_log` y avisar si hay un problema
  /// (HU-SYNC-009). Si lanza, la verificación no se da por fallida.
  Future<void> Function(IntegrityReport informe)? alVerificarIntegridad;

  /// OAuth con Google Drive (HU-SYNC-004).
  Future<bool> authorize() => _archive.authorize();

  Future<bool> get isAuthorized => _archive.isAuthorized;

  /// Una verificación encontró la cadena rota: el próximo backup parte de una
  /// base nueva aunque la cadena parezca sana por sus enlaces (un blob
  /// corrupto no se ve en los metadatos si el archivo no informa su hash).
  bool _regenerarBase = false;

  /// Hay una base nueva pendiente por un problema de integridad (HU-SYNC-009).
  bool get regenerarBase => _regenerarBase;

  /// Un backup incremental, o el completo si todavía no hay cadena, si la
  /// cadena no sirve o si le toca rotar la base (HU-SYNC-005).
  ///
  /// [watermark] queda guardado en la entrada: es de donde arranca la
  /// reconciliación de §7 fase 3. Sin él se pide a [watermarkProvider].
  Future<BackupEntry> backupNow({String? watermark}) {
    // Uno por vez. Dos backups en paralelo leen la misma punta y suben los dos
    // con el mismo padre: eso es un fork, y un fork deja la cadena entera
    // inservible porque no hay forma de saber cuál rama es la buena. Pasa solo
    // con que el colportor toque "hacer backup" mientras corre el del cierre de
    // jornada.
    return _encadenar(() => _backupNow(watermark));
  }

  Future<BackupEntry> _backupNow(String? watermark) async {
    // El reloj del teléfono, antes de leer la DB: ver [BackupEntry.exportedAt].
    final inicio = _clock();
    final mark = watermark ?? await watermarkProvider?.call() ?? '';

    // Solo la cadena de esta llave. Lo que dejó otra instalación en la misma
    // carpeta de Drive (el teléfono viejo de la persona, con otra DEK) ni se
    // encadena ni se poda: para este servicio no existe.
    final (:llave, entradas: existentes) = await _propias();
    final cadena = buildChain(existentes);

    // Una cadena rota no se extiende: agregarle un eslabón encima haría que el
    // restore falle igual, pero más tarde y con más datos adentro.
    final rotar = _regenerarBase || !cadena.ok || _tocaRotar(cadena, inicio);
    final punta = rotar ? null : cadena.tip;

    final crudo = await _snapshot.export(
      since: punta == null ? null : (punta.exportedAt ?? punta.createdAt),
    );
    final cifrado = await _crypto.encrypt(crudo);

    // La subida es todo o nada: si se corta, no hay entrada y la cadena
    // anterior sigue siendo la vigente (HU-SYNC-005, «manifest intacto»).
    final entrada = await _archive.upload(
      payload: cifrado,
      parentId: punta?.id,
      watermark: mark,
      exportedAt: inicio,
      keyId: llave,
    );

    if (punta == null) {
      _regenerarBase = false;
      // La base nueva reemplaza a la cadena entera, sana o rota. Se confirma
      // que quedó bien antes de tocar nada: la vieja se mantiene hasta que la
      // nueva está confirmada.
      if (!entrada.corrupta) {
        await _podar([...existentes]);
      }
    } else if (cadena.superseded.isNotEmpty) {
      // Restos de una rotación anterior cuya poda se cortó.
      await _podar(cadena.superseded);
    }

    try {
      await alTerminarUnBackup?.call(entrada);
    } on Object {
      // Ver [alTerminarUnBackup]: el backup ya está hecho.
    }
    return entrada;
  }

  /// Las entradas de Drive que cifró esta llave, y solo esas.
  ///
  /// Las que traen otro identificador, o ninguno, quedan afuera: no se
  /// extienden, no se podan ni cuentan para la integridad. Si no hay cadena
  /// propia, el respaldo arranca la suya al lado y la ajena queda entera
  /// (nunca se pierde una persona: ante la duda, no se borra).
  ///
  /// Primero se lista y después se pide la llave: sin Drive (sin token) la falla es la de Drive, y
  /// la DEK no se toca para nada.
  Future<({String llave, List<BackupEntry> entradas})> _propias() async {
    final todas = await _archive.list();
    final llave = await _crypto.keyId();
    return (
      llave: llave,
      entradas: [
        for (final e in todas)
          if (e.keyId == llave) e,
      ],
    );
  }

  bool _tocaRotar(ChainStatus cadena, DateTime ahora) {
    final base = cadena.ordered.first;
    final incrementales = cadena.ordered.length - 1;
    if (incrementales >= policy.maxPatches) return true;
    final desde = base.exportedAt ?? base.createdAt;
    return !ahora.difference(desde).isNegative &&
        ahora.difference(desde) >= policy.maxBaseAge;
  }

  /// Borra [viejas]. De mejor esfuerzo: una poda que se corta deja basura, no
  /// pierde nada, y el próximo backup la vuelve a intentar.
  Future<void> _podar(List<BackupEntry> viejas) async {
    for (final e in viejas) {
      try {
        await _archive.delete(e.id);
      } on Object {
        // Se reintenta en el próximo backup (queda como `superseded`).
      }
    }
  }

  /// Integridad de la cadena (HU-SYNC-009).
  ///
  /// Verifica los enlaces **y** los hashes: una entrada que existe pero está
  /// corrupta rompe el restore igual que una que falta, y solo se nota
  /// comparando el hash. Si el archivo informa el hash que calculó
  /// ([BackupEntry.storedHash], Drive lo hace) se compara sin bajar nada; si no,
  /// se baja el blob.
  Future<ChainStatus> verifyChain({bool checkContent = true}) async =>
      _verificar((await _propias()).entradas, checkContent: checkContent);

  Future<ChainStatus> _verificar(
    List<BackupEntry> entradas, {
    required bool checkContent,
  }) async {
    final cadena = buildChain(entradas);
    if (!cadena.ok || !checkContent) return cadena;

    for (final entrada in cadena.ordered) {
      // Con el hash remoto, `buildChain` ya comparó: acá no hay nada que bajar.
      if (entrada.storedHash != null) continue;
      final bytes = await _archive.download(entrada.id);
      if (_crypto.digest(bytes) != entrada.contentHash) {
        return ChainStatus(
          problems: const {ChainProblem.corrupt},
          ordered: const [],
          corruptIds: {entrada.id},
        );
      }
    }
    return cadena;
  }

  /// La verificación periódica (HU-SYNC-009): mira la cadena, deja el
  /// resultado en [alVerificarIntegridad] y, si encontró un problema, deja
  /// dicho que el próximo backup es una base nueva.
  ///
  /// Un fallo de red al verificar **no** es un hallazgo: sale como excepción y
  /// no cambia nada. Sin backups tampoco: no hay cadena que verificar.
  Future<IntegrityReport> verifyIntegrity() {
    // Serializada con los backups: no se verifica una cadena mientras se la
    // extiende.
    return _encadenar(() async {
      final entradas = (await _propias()).entradas;
      final estado = await _verificar(entradas, checkContent: true);
      final informe = IntegrityReport(
        status: estado,
        checkedAt: _clock(),
        hasBackup: entradas.isNotEmpty,
        entries: entradas.length,
      );
      if (informe.needsRebase) _regenerarBase = true;
      try {
        await alVerificarIntegridad?.call(informe);
      } on Object {
        // El resultado ya está en `informe`.
      }
      return informe;
    });
  }

  /// Reconstruye la DB desde la cadena (HU-SYNC-006).
  ///
  /// Devuelve la entrada de la punta —de cuándo son los datos— o `null` si no
  /// había nada usable.
  Future<BackupEntry?> restore() => _encadenar(_restore);

  Future<BackupEntry?> _restore() async {
    // Sin filtrar por llave: qué hacer cuando Drive tiene más de una cadena (la del teléfono viejo y
    // la del nuevo) es de la restauración (#186, HU-SYNC-006), no de este backup.
    final cadena = await _verificar(await _archive.list(), checkContent: true);
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

  /// Lo último que se encadenó. Nunca falla: solo marca cuándo terminó.
  Future<void>? _enCurso;

  /// Corre [trabajo] cuando termine lo que ya estaba en curso, pase lo que pase
  /// con eso. Backups, verificaciones y restore no se pisan.
  Future<T> _encadenar<T>(Future<T> Function() trabajo) {
    final anterior = _enCurso;
    final resultado = () async {
      if (anterior != null) await anterior;
      return trabajo();
    }();
    _enCurso = resultado.then<void>((_) {}, onError: (Object _) {});
    return resultado;
  }
}
