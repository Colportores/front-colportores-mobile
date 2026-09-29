/// Operación de un cambio encolado para el sync (el `Op` de contrato-sync-engine §3).
enum OperacionSync { insert, update, delete }

/// Punto de enganche de la capa `data` con el motor de sync: el `engine.stage(entidad, op,
/// payload)` de contrato-sync-engine §3.
///
/// **Se llama dentro de la misma transacción** en la que se escribe la fila de negocio: si
/// [encolar] falla, la transacción se revierte y la fila tampoco queda, porque un dato guardado
/// que nunca sube es peor que un alta que se reintenta.
///
/// El motor (`sync_engine`, PR #40) y su cola sobre la DB (PR #41) todavía no están en `develop`.
/// El adaptador que llama a `engine.stage` llega con el hito I1 (#178, Bruno); hasta entonces no
/// hay implementación de producción y los tests usan `EncoladorSyncEnMemoria`.
abstract interface class EncoladorSync {
  /// Encola [operacion] sobre la fila de [entidad] (nombre de la tabla del cloud: `ubicacion`,
  /// `espacio`, …) con [payload], la fila entera con los nombres de columna del cloud.
  Future<void> encolar(String entidad, OperacionSync operacion, Map<String, Object?> payload);
}
