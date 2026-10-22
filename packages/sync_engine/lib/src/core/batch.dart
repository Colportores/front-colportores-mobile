import 'dart:convert';

import 'model.dart';
import 'queue.dart';

/// Tope típico de un lote (§5.5, RR-02). No es un tope de cantidad: 200 visitas
/// livianas pesan menos que 20 ventas con items.
const kMaxBatchBytes = 1024 * 1024;

/// Tamaño aproximado de un job serializado.
int jobBytes(SyncJob job) => utf8
    .encode(jsonEncode({
      'client_op_id': job.clientOpId,
      'entity': job.entity,
      'op': job.op.name,
      'sync_version': job.syncVersion,
      'payload': job.payload,
    }))
    .length;

int batchBytes(PushBatch batch) =>
    batch.jobs.fold(0, (n, job) => n + jobBytes(job));

/// Parte los jobs en lotes bajo [maxBytes], **conservando el orden recibido**.
///
/// El orden es la garantía de §5.5: los jobs de una misma entidad suben en
/// orden de creación. Como no se reordena nada, un `update` nunca puede
/// adelantarse al `insert` de su propia fila.
///
/// Un job que por sí solo pasa el tope viaja igual, en un lote propio: partirlo
/// no es posible y descartarlo perdería una venta. Que el backend lo rechace y
/// quede `INVALID`, visible, es mejor que desaparecer en silencio.
///
/// **Una fila viaja una sola vez por lote** (§5.4). Dos escrituras de la misma
/// fila en un lote esperan la misma `sync_version`, y en el servidor la segunda
/// vuelve `conflict`: el LWW la pisaría con la primera. Pasa cuando la segunda
/// se encoló mientras la primera viajaba y ese viaje falló. El lote se corta
/// ahí, y la segunda sale en el siguiente con la versión que devolvió la
/// primera.
List<PushBatch> buildBatches(
  List<QueuedJob> jobs, {
  int maxBytes = kMaxBatchBytes,
}) {
  final lotes = <PushBatch>[];
  var actual = <SyncJob>[];
  var filas = <(String, String)>{};
  var bytes = 0;

  for (final encolado in jobs) {
    final job = encolado.job;
    final peso = jobBytes(job);
    final fila = job.rowPk == null ? null : (job.entity, job.rowPk!);
    if (actual.isNotEmpty &&
        (bytes + peso > maxBytes || (fila != null && filas.contains(fila)))) {
      lotes.add(PushBatch(actual));
      actual = [];
      filas = {};
      bytes = 0;
    }
    actual.add(job);
    if (fila != null) filas.add(fila);
    bytes += peso;
  }

  if (actual.isNotEmpty) lotes.add(PushBatch(actual));
  return lotes;
}
