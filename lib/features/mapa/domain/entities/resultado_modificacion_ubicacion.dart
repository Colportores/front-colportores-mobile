import 'package:equatable/equatable.dart';

import 'ubicacion.dart';

/// Cómo terminó un pedido de modificación de ubicación (HU-UBI-004) que no fue un error.
///
/// Además de la modificación hecha hay tres resultados en los que **no se escribió nada**: no hubo
/// cambios, falta una confirmación del colportor o hay candidatas a duplicado. No son `Failure`:
/// son pasos normales del flujo, y un `switch` sobre esta clase sellada obliga a la pantalla a
/// contemplar los cuatro.
sealed class ResultadoModificacionUbicacion extends Equatable {
  const ResultadoModificacionUbicacion();
}

/// La ubicación quedó modificada en el teléfono y el cambio quedó encolado para el sync.
final class UbicacionModificada extends ResultadoModificacionUbicacion {
  const UbicacionModificada({required this.ubicacion, this.reactivada = false});

  /// La ubicación como quedó.
  final Ubicacion ubicacion;

  /// Estaba dada de baja y el colportor confirmó reactivarla al guardar (S18).
  final bool reactivada;

  @override
  List<Object?> get props => [ubicacion, reactivada];
}

/// Los valores pedidos son los que la ubicación ya tiene: no se escribió ni se encoló nada (no se
/// sube un cambio vacío).
final class ModificacionSinCambios extends ResultadoModificacionUbicacion {
  const ModificacionSinCambios({required this.ubicacion});

  final Ubicacion ubicacion;

  @override
  List<Object?> get props => [ubicacion];
}

/// Qué confirmación explícita pide la HU antes de guardar.
enum ConfirmacionModificacion {
  /// La ubicación está en baja: "¿Reactivarla al guardar?" (S18, ajuste PO 2026-05-19).
  reactivar,

  /// Cambia el `ciudad_id`: reubica la ubicación geográficamente.
  cambioCiudad,

  /// Las coordenadas se mueven más de `ModificarUbicacionUseCase.umbralDesplazamientoMetros`.
  desplazamiento,
}

/// Falta al menos una confirmación: no se escribió nada. La pantalla muestra los avisos de
/// [pendientes] y repite el pedido con esas confirmaciones en `confirmadas`.
final class ModificacionRequiereConfirmacion extends ResultadoModificacionUbicacion {
  const ModificacionRequiereConfirmacion({required this.pendientes, this.desplazamientoMetros});

  /// Nunca vacío.
  final Set<ConfirmacionModificacion> pendientes;

  /// Cuánto se movió el punto; viene cuando [pendientes] incluye
  /// [ConfirmacionModificacion.desplazamiento].
  final double? desplazamientoMetros;

  /// Texto literal del criterio de aceptación.
  static const avisoReactivar = 'Esta ubicación está en baja. ¿Reactivarla al guardar?';

  /// La HU pide "advertir y pedir confirmación", sin texto: para confirmar con Cristian.
  static const avisoCambioCiudad =
      'Cambiar la ciudad reubica esta ubicación en otra zona del mapa. ¿Confirmás el cambio?';

  /// Texto literal del criterio de aceptación, con la distancia redondeada a metros.
  static String avisoDesplazamiento(double metros) =>
      'Las nuevas coordenadas están a ${metros.round()}m de la ubicación original. ¿Confirmás?';

  @override
  List<Object?> get props => [pendientes, desplazamientoMetros];
}

/// La edición dejaría a la ubicación cerca de otra que parece la misma (HU-UBI-004, caso borde;
/// HU-UBI-006): no se escribió nada. La pantalla muestra las candidatas y, si el colportor sigue,
/// repite el pedido con una justificación.
final class ModificacionConDuplicados extends ResultadoModificacionUbicacion {
  const ModificacionConDuplicados({required this.candidatas});

  /// De la más cercana a la más lejana; nunca vacía. Nunca incluye a la ubicación editada.
  final List<Ubicacion> candidatas;

  @override
  List<Object?> get props => [candidatas];
}
