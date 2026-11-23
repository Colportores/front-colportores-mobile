import '../entities/alquiler.dart';

/// «Mi alquiler», calculado en el teléfono y al día solo (HU-CTA-007, offline-first): el monto de cada
/// campaña, lo pagado y lo que falta salen de las réplicas locales del pull.
///
/// El `Stream` emite lo de ahora al suscribirse y uno nuevo **solo si cambió**: al bajar un pago
/// validado, o un cambio del monto, quien mira se actualiza sin recargar. Si la base no se puede leer,
/// falla con `FailureAlquilerNoDisponible` y nunca emite «sin alquiler»: «no pude calcular» no es «tu
/// campaña no cobra».
abstract interface class AlquilerRepository {
  /// El alquiler del colportor [colportorId] en cada campaña en la que está inscripto.
  Stream<AlquilerDelColportor> observar(String colportorId);
}
