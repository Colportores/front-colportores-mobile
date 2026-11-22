import '../entities/detalle_de_mi_plata.dart';

/// De dónde sale el detalle de «Mi plata» (HU-CTA-003). La implementación lee el teléfono.
abstract interface class DetalleDeMiPlataRepository {
  /// El detalle del colportor [colportorId] ahora y de nuevo cada vez que cambia una venta, un cobro
  /// o una devolución. Si no se puede calcular, el `Stream` falla con `FailureCuentaNoDisponible`: no
  /// emite ceros que se lean como «no tenés nada».
  Stream<DetalleDeMiPlata> observar(String colportorId);
}
