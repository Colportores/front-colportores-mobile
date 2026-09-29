import '../encolador_sync.dart';

/// Un cambio encolado por [EncoladorSyncEnMemoria].
typedef CambioEncolado = ({String entidad, OperacionSync operacion, Map<String, Object?> payload});

/// [EncoladorSync] en memoria, para tests y para desarrollar sin el motor de sync.
///
/// [fallarCon] simula un motor que rechaza el `stage()` (apagado, entidad sin registrar): la
/// transacción que lo llamó se tiene que revertir.
final class EncoladorSyncEnMemoria implements EncoladorSync {
  EncoladorSyncEnMemoria({this.fallarCon});

  /// Si no es `null`, [encolar] lo lanza en vez de encolar.
  Object? fallarCon;

  /// Lo encolado, en orden.
  final encolados = <CambioEncolado>[];

  @override
  Future<void> encolar(
    String entidad,
    OperacionSync operacion,
    Map<String, Object?> payload,
  ) async {
    final error = fallarCon;
    if (error != null) throw error;
    encolados.add((entidad: entidad, operacion: operacion, payload: Map.unmodifiable(payload)));
  }
}
