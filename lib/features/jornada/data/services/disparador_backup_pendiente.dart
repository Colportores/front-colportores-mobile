import '../../../../core/logging/app_logger.dart';
import '../../domain/services/disparador_backup.dart';

/// [DisparadorBackup] mientras no exista el backup automático (HU-SYNC-005): registra el pedido
/// en el log y no hace nada más.
///
/// TODO(#74): reemplazar por la implementación de HU-SYNC-005 (carril de sync) cuando entre; es
/// la que comprueba Wi-Fi y batería ≥ 30 % antes de correr. El cierre de la jornada no cambia.
final class DisparadorBackupPendiente implements DisparadorBackup {
  DisparadorBackupPendiente({AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  @override
  Future<void> solicitar(String colportorId) async {
    _log.info(LogModulo.backup, 'BACKUP_NO_DISPONIBLE', 'backup pedido al cerrar la jornada', {
      'user_id': colportorId,
    });
  }
}
