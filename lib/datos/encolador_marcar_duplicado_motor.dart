import 'package:sync_engine/sync_engine.dart';

import '../features/mapa/domain/services/encolador_marcar_duplicado.dart';

/// [EncoladorMarcarDuplicado] sobre el motor de sync: el trabajo «marcar como duplicado» de
/// contrato-sync-engine §6.2 (`entity: "ubicacion"`, `op: "marcar_como_duplicado"`, `payload:
/// {duplicada_id, conservada_id}`), que `sync_push` aplica como `marcar_como_duplicado(B, A)`.
///
/// La unión local lo llama **dentro de su transacción**, y `stage` escribe el job en `sync_queue`
/// por la misma conexión (`DriftJobStore`), así que entra en ella: o quedan la unión y su trabajo,
/// o ninguno de los dos. Mismo criterio que `EncoladorSyncMotor`.
///
/// No lleva `sync_version` (§6.2): el motor la saca del job y le devuelve a B la que contesta el
/// servidor.
final class EncoladorMarcarDuplicadoMotor implements EncoladorMarcarDuplicado {
  const EncoladorMarcarDuplicadoMotor(this._motor);

  final SyncEngine _motor;

  @override
  Future<void> encolarMarcarDuplicado({
    required String duplicadaId,
    required String conservadaId,
  }) async {
    await _motor.stage('ubicacion', Op.marcarComoDuplicado, {
      'duplicada_id': duplicadaId,
      'conservada_id': conservadaId,
    });
  }
}
