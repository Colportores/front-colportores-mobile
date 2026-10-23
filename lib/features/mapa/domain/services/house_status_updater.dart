import '../entities/house_status.dart';

/// El servicio que mantiene la cache `house_status` (ADR-003: «la lógica de prioridad vive en un
/// único servicio»). Lo implementa `HouseStatusUpdaterDrift`.
///
/// **Se llama dentro de la transacción de la escritura que cambia el color de la casa** (una
/// agenda o una visita, y más adelante una venta, una entrega o un cobro): R-UB08, «las escrituras
/// actualizan la cache en la misma transacción local, no al renderizar el mapa». Si el recálculo
/// falla, la transacción se revierte y la escritura tampoco queda: la cache nunca se atrasa
/// respecto de lo que hay en el teléfono.
abstract interface class HouseStatusUpdater {
  /// Recalcula el color de [ubicacionId] con todo lo que hoy hay en el teléfono y deja la fila de
  /// `house_status` como corresponde, encolando su subida (sin PII):
  ///
  /// - sin fila y con color → la crea;
  /// - con fila y otro color (o otro punto o tipo) → la actualiza;
  /// - con fila y sin ningún estado que la pinte → la da de baja (la casa vuelve a «Sin visita»);
  /// - sin cambio → no escribe ni encola nada.
  ///
  /// [ahora] es el instante de la escritura que lo motivó y [colportorId] quien la hizo (el
  /// `created_by` de una fila nueva). Una ubicación que no está en el teléfono o está dada de baja
  /// no se toca: devuelve `null`.
  ///
  /// Devuelve la fila resultante, o `null` si la casa quedó sin fila.
  Future<HouseStatus?> recalcular(
    String ubicacionId, {
    required DateTime ahora,
    required String colportorId,
  });
}
