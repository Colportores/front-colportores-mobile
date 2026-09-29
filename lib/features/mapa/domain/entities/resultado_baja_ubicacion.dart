import 'package:equatable/equatable.dart';

import 'pendientes_ubicacion.dart';
import 'ubicacion.dart';

/// Cómo terminó un pedido de baja de ubicación (HU-UBI-005) que no fue un error.
sealed class ResultadoBajaUbicacion extends Equatable {
  const ResultadoBajaUbicacion();
}

/// La ubicación quedó dada de baja en el teléfono (`deleted_at`) y el tombstone quedó encolado.
/// Sus espacios y personas no se tocan (HU-UBI-005: sin cascada).
final class UbicacionDadaDeBaja extends ResultadoBajaUbicacion {
  const UbicacionDadaDeBaja({required this.ubicacion});

  final Ubicacion ubicacion;

  @override
  List<Object?> get props => [ubicacion];
}

/// Ya estaba de baja (un doble toque cuyo primer toque entró): nada que escribir ni encolar.
final class BajaSinCambios extends ResultadoBajaUbicacion {
  const BajaSinCambios({required this.ubicacion});

  final Ubicacion ubicacion;

  @override
  List<Object?> get props => [ubicacion];
}

/// Tiene pendientes: no se escribió nada. La pantalla muestra [pendientes] (`resumen`) y, tras la
/// segunda confirmación, repite el pedido con `confirmaPendientes: true`.
final class BajaRequiereConfirmacion extends ResultadoBajaUbicacion {
  const BajaRequiereConfirmacion({required this.pendientes});

  /// Nunca vacío (`hayPendientes`).
  final PendientesUbicacion pendientes;

  @override
  List<Object?> get props => [pendientes];
}
