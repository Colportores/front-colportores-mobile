import '../encolador_sync.dart';

/// Un cambio encolado por [EncoladorSyncEnMemoria].
typedef CambioEncolado = ({String entidad, OperacionSync operacion, Map<String, Object?> payload});

/// [EncoladorSync] en memoria, para tests y para desarrollar sin el motor de sync.
///
/// [fallarCon] simula un motor que rechaza el `stage()` (apagado, entidad sin registrar): la
/// transacción que lo llamó se tiene que revertir.
///
/// **No es transaccional**: lo que encoló antes de una falla queda en [encolados] aunque la
/// transacción de la app se revierta. Con el motor real (`stage()` escribe en `sync_queue`, en la
/// misma DB) ese job se revierte con todo; el adaptador de I1 tiene que llamarlo adentro de la
/// transacción, y eso este fake no lo puede verificar.
final class EncoladorSyncEnMemoria implements EncoladorSync {
  EncoladorSyncEnMemoria({this.fallarCon, this.fallarDespuesDe = 0});

  /// Si no es `null`, [encolar] lo lanza en vez de encolar (después de [fallarDespuesDe] éxitos).
  Object? fallarCon;

  /// Cuántas llamadas encolan bien antes de empezar a fallar con [fallarCon].
  int fallarDespuesDe;

  /// Lo encolado, en orden.
  final encolados = <CambioEncolado>[];

  @override
  Future<void> encolar(
    String entidad,
    OperacionSync operacion,
    Map<String, Object?> payload,
  ) async {
    final error = fallarCon;
    if (error != null && encolados.length >= fallarDespuesDe) throw error;
    encolados.add((entidad: entidad, operacion: operacion, payload: Map.unmodifiable(payload)));
  }
}
