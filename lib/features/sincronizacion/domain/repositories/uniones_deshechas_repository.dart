/// Qué trabajos de la cola de sync son de una unión de duplicados que el teléfono ya deshizo
/// (HU-UBI-006: el servidor rechazó «marcar como duplicado» y el par quedó separado). Esos trabajos
/// siguen rechazados y a la vista, pero **no se reintentan**: el servidor uniría lo que el teléfono
/// separó (decisión del 10/11, #688 P1).
abstract interface class UnionesDeshechasRepository {
  /// Los `id` de trabajo (los de `sync_queue`) de las uniones deshechas.
  Future<Set<String>> trabajos();
}

/// Sin uniones que cuidar (no hay DB local abierta, o un test que no las usa).
final class SinUnionesDeshechas implements UnionesDeshechasRepository {
  const SinUnionesDeshechas();

  @override
  Future<Set<String>> trabajos() async => const <String>{};
}
