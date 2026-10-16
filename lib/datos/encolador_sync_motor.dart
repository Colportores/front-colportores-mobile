import 'package:sync_engine/sync_engine.dart';

import '../core/sync/encolador_sync.dart';

/// [EncoladorSync] sobre el motor de sync: el `engine.stage(entidad, op, payload)` de
/// contrato-sync-engine §3.
///
/// La capa `data` lo llama **dentro de la transacción** de la escritura de negocio, y `stage`
/// escribe el job en `sync_queue` por la misma conexión (`DriftJobStore`), así que entra en esa
/// transacción: o se guardan la fila y su job, o ninguno de los dos.
///
/// La `sync_version` esperada de un `update` o un `delete` (§5.4) es la de la fila que la app
/// tiene: la toma del payload, que es la fila entera con los nombres del cloud. El motor la
/// mantiene al día después de cada subida (`LocalStorePort.applyVersions`).
final class EncoladorSyncMotor implements EncoladorSync {
  const EncoladorSyncMotor(this._motor);

  final SyncEngine _motor;

  @override
  Future<void> encolar(
    String entidad,
    OperacionSync operacion,
    Map<String, Object?> payload,
  ) async {
    final op = switch (operacion) {
      OperacionSync.insert => Op.insert,
      OperacionSync.update => Op.update,
      OperacionSync.delete => Op.delete,
    };
    await _motor.stage(
      entidad,
      op,
      payload,
      syncVersion: op == Op.insert ? null : (payload['sync_version'] as num?)?.toInt(),
    );
  }
}
