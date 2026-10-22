// El reporte de `engine.recover()` (§7).

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
  });

  /// De cuándo son los datos del backup restaurado. `null` si no había backup.
  final DateTime? backupDate;

  /// Jobs de `sync_queue` que volvieron a existir con el restore y se
  /// reenviaron al backend.
  final int replayedJobs;

  /// Entidad → filas traídas de Supabase en la reconciliación.
  final Map<String, int> pulledEntities;

  /// Qué quedó afuera. `null` cuando no había backup: ahí la pérdida no es una
  /// ventana, es toda la PII.
  final LostWindow? lostWindow;

  /// Por qué no se pudo usar el backup, si la cadena estaba rota.
  final String chainProblem;

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
