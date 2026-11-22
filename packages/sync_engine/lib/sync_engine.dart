/// Motor de sincronización y backup de Colportaje App.
///
/// Núcleo Dart puro: corre en `dart test` sin emulador ni dispositivo (§5.9).
/// Lo que toca la plataforma vive detrás de un puerto (R-A2) y se implementa en
/// `lib/src/adapters/`, el único lugar donde puede aparecer un plugin (R-A1).
library;

export 'src/core/adapter.dart';
export 'src/core/backup.dart';
export 'src/core/backup_service.dart';
export 'src/core/batch.dart';
export 'src/core/engine.dart';
export 'src/core/errors.dart';
export 'src/core/model.dart';
export 'src/core/ports.dart';
export 'src/core/queue.dart';
export 'src/core/recover.dart';
export 'src/core/spec.dart';
export 'src/core/uuid.dart';
export 'src/core/wire.dart';
