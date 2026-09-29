import '../../domain/entities/duplicado_ubicacion.dart';

/// Persistencia local de las decisiones sobre pares de posibles duplicados (HU-UBI-006).
abstract interface class ParesDuplicadosLocalDataSource {
  /// Cuándo se decidió cada par, por `ParDuplicado.clave`.
  Future<Map<String, DateTime>> decididos();

  /// Guarda [decision] sobre el par [ubicacionId1]–[ubicacionId2] (en cualquier orden) con fecha
  /// [decididoEn], pisando la anterior si había.
  Future<void> decidir(
    String ubicacionId1,
    String ubicacionId2,
    DecisionParDuplicado decision, {
    required DateTime decididoEn,
  });
}
