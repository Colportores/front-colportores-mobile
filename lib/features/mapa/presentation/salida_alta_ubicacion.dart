import '../domain/entities/ubicacion.dart';

/// Cómo se cerró el alta de ubicación.
sealed class SalidaAltaUbicacion {
  const SalidaAltaUbicacion();
}

/// La ubicación quedó registrada: el mapa vuelve con ella seleccionada.
final class UbicacionCreada extends SalidaAltaUbicacion {
  const UbicacionCreada(this.ubicacion);

  final Ubicacion ubicacion;
}

/// El colportor eligió «Reutilizar esta» (o «Abrir la existente») en el aviso de duplicado: el mapa
/// abre esa ubicación con la vista previa, sin modificar sus datos.
final class UbicacionReutilizada extends SalidaAltaUbicacion {
  const UbicacionReutilizada(this.ubicacionId);

  final String ubicacionId;
}
