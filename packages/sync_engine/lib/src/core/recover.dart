// El reporte de `engine.recover()` (§7) y lo que el wizard necesita mientras
// corre: el avance por paso y la cancelación.

import 'backup_service.dart';

/// Una cadena de respaldo para restaurar con `engine.recover(sources: …)`
/// (contrato §7, «Varios respaldos de otros teléfonos»): el servicio que tiene
/// la llave que la abre y la llave de la cadena en Drive.
class RecoverySource {
  const RecoverySource({required this.backup, this.keyId});

  /// El servicio con el cifrado de esa cadena.
  final BackupService backup;

  /// La llave de la cadena ([CryptoPort.keyId]); `null` toma todas las
  /// entradas del archivo.
  final String? keyId;
}

/// La ventana de datos que no se puede recuperar: lo creado después del último
/// backup que tampoco alcanzó a sincronizar.
///
/// El contrato no promete recuperarla. La mitigación no está en el restore sino
/// en la frecuencia: backup al cierre de jornada y sync `critical` en cada venta
/// achican la ventana a horas.
class LostWindow {
  const LostWindow({required this.from, required this.to});

  /// Fecha del último backup.
  final DateTime from;

  /// Ahora: el momento de la recuperación.
  final DateTime to;

  Duration get length => to.difference(from);

  @override
  String toString() => 'LostWindow($from → $to, ${length.inHours} h)';
}

/// Lo que la app muestra en el wizard de primer arranque (§7 fase 5).
class RecoveryReport {
  const RecoveryReport({
    required this.pulledEntities,
    this.backupDate,
    this.replayedJobs = 0,
    this.lostWindow,
    this.chainProblem = '',
    this.partial = false,
    this.partsRestored = 0,
    this.partsTotal = 0,
    this.backupDates = const [],
    this.skippedChains = 0,
  });

  /// De cuándo son los datos del backup restaurado. `null` si no había backup.
  /// Con varias cadenas, la fecha más nueva.
  final DateTime? backupDate;

  /// De cuándo es cada cadena restaurada (una por respaldo de otro teléfono).
  /// Vacío si no se restauró ninguna en esta llamada.
  final List<DateTime> backupDates;

  /// Cuántas cadenas pedidas se saltearon porque no tenían una base usable
  /// (rota o que no se descifra). A diferencia de [backupDates], también se
  /// informa en el reintento de una recuperación cuyo restore ya había pasado:
  /// sale de la marca guardada con la de recuperación.
  final int skippedChains;

  /// Jobs de `sync_queue` que volvieron a existir con el restore y se
  /// reenviaron al backend.
  final int replayedJobs;

  /// Entidad → filas traídas de Supabase en la reconciliación.
  final Map<String, int> pulledEntities;

  /// Qué quedó afuera. `null` cuando no había backup: ahí la pérdida no es una
  /// ventana, es toda la PII.
  final LostWindow? lostWindow;

  /// Por qué no se pudo usar el backup, o no se pudo usar entero, si la cadena
  /// estaba rota.
  final String chainProblem;

  /// El restore se cortó en un eslabón dañado (HU-SYNC-006, «Patch corrupto en
  /// medio de la cadena»): se aplicó hasta el último válido. [backupDate] es
  /// hasta cuándo llega lo restaurado; lo posterior quedó afuera.
  final bool partial;

  /// Cuántas partes (la base y los incrementales) se aplicaron.
  final int partsRestored;

  /// Cuántas partes tenía la cadena. Si es más que [partsRestored], las demás
  /// no entraron.
  final int partsTotal;

  int get pulledRows => pulledEntities.values.fold(0, (n, filas) => n + filas);

  bool get hadBackup => backupDate != null;

  /// §7: sin backup, `persona` y `nota` se pierden de forma permanente. El
  /// reporte lo dice sin eufemismos, y es el argumento con el que la app
  /// insiste en autorizar el backup en el onboarding.
  bool get lostPersonalData => !hadBackup;

  @override
  String toString() => 'RecoveryReport(backup: $backupDate, '
      'replay: $replayedJobs, filas: $pulledRows, perdido: $lostWindow'
      '${lostPersonalData ? ", SIN BACKUP: persona y nota se perdieron" : ""})';
}

/// En qué paso va `engine.recover()` (el asistente de la vista 34).
enum RecoveryPhase {
  /// Mirando qué hay en Drive.
  searching,

  /// Bajando y verificando las partes del respaldo.
  downloading,

  /// Ya está todo abajo: armando la copia en el archivo temporal y pasándola a
  /// la DB. Desde acá ya no se puede cancelar.
  applying,

  /// Reenviando lo que estaba en la cola del respaldo.
  replaying,

  /// Trayendo de Supabase lo que subió después del respaldo.
  reconciling,

  /// Terminó.
  done,
}

/// El avance de `engine.recover()`. [done] de [total] cuenta las partes del
/// respaldo en [RecoveryPhase.downloading] (el «12/15 partes» de la pantalla).
class RecoveryProgress {
  const RecoveryProgress(
    this.phase, {
    this.done = 0,
    this.total = 0,
    this.waitingForNetwork = false,
  });

  final RecoveryPhase phase;
  final int done;
  final int total;

  /// Se cortó la red: el motor espera a que vuelva y sigue desde la parte
  /// [done] (HU-SYNC-006, «Fallo de red durante restore»).
  final bool waitingForNetwork;

  /// Hasta el final de la descarga se puede cancelar sin consecuencias.
  bool get canCancel =>
      phase == RecoveryPhase.searching || phase == RecoveryPhase.downloading;

  @override
  String toString() => 'RecoveryProgress(${phase.name} $done/$total'
      '${waitingForNetwork ? ", sin red" : ""})';
}

typedef RecoveryProgressCallback = void Function(RecoveryProgress progreso);

/// Cancelar un `recover()` que está bajando el respaldo (HU-SYNC-006,
/// «Cancelación por el usuario»). Cancelar antes de que empiece a aplicarse
/// descarta lo bajado y deja la DB como estaba; después de ese punto no tiene
/// efecto: el reemplazo ya es todo o nada y no se interrumpe.
class RecoveryCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  /// Lanza [RecoveryCancelled] si ya se canceló.
  void throwIfCancelled() {
    if (isCancelled) throw const RecoveryCancelled();
  }
}

/// El `recover()` se canceló antes de tocar la DB.
class RecoveryCancelled implements Exception {
  const RecoveryCancelled();

  @override
  String toString() => 'RecoveryCancelled()';
}
