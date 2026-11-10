import '../entities/resumen_de_cuenta.dart';

/// El resumen de Mi Cuenta, calculado en el teléfono y al día solo (HU-CTA-001, offline-first).
///
/// El `Stream` emite el resumen de ahora al suscribirse y uno nuevo **solo si cambió**: al registrar,
/// anular o dar de baja un cobro, una venta o una devolución, quien mira se actualiza sin recargar.
/// Si la base no se puede leer, falla con `FailureCuentaNoDisponible` y nunca emite ceros: «no pude
/// calcular» no es «no tenés nada».
abstract interface class ResumenDeCuentaRepository {
  /// El resumen de las ventas y cobros del colportor [colportorId].
  Stream<ResumenDeCuenta> observar(String colportorId);
}
