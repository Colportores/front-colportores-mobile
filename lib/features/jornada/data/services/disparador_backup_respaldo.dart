import 'dart:async';

import '../../../respaldo/domain/services/servicio_respaldo.dart';
import '../../domain/services/disparador_backup.dart';

/// [DisparadorBackup] sobre el respaldo en Drive (HU-JOR-002 → HU-SYNC-005): al cerrar la jornada
/// pide un respaldo automático y vuelve enseguida.
///
/// Las condiciones (Drive conectado, Wi-Fi, batería ≥ 30 %) las pone [ServicioRespaldo]. Si no se
/// cumplen, el respaldo queda para la próxima vuelta a la app (24 horas, `RevisionDelRespaldo`): el
/// cierre ya quedó guardado igual. El pedido corre aparte y nunca lanza, así que el cierre no espera
/// ni se rompe por él.
final class DisparadorBackupRespaldo implements DisparadorBackup {
  const DisparadorBackupRespaldo(this._servicio);

  final ServicioRespaldo _servicio;

  @override
  Future<void> solicitar(String colportorId) async {
    unawaited(_servicio.respaldar(OrigenRespaldo.cierreDeJornada));
  }
}
