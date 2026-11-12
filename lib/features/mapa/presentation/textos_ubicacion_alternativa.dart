/// Los textos de la ubicación alternativa de cobranza (HU-UBI-013). Los rótulos y avisos son los de la
/// HU, tal cual; la vista 22 que los dibuja todavía no está en `disenio-vistas/`, así que ninguna
/// pantalla los usa aún.
abstract final class TextosUbicacionAlternativa {
  /// Acción de la ficha de la persona (escenario «Asignar ubicación alternativa existente»).
  static const establecer = 'Establecer ubicación alternativa de cobranza';

  /// Escenario «Quitar ubicación alternativa».
  static const quitar = 'Quitar ubicación alternativa';

  /// Banner del escenario «alternativa dada de baja»; HU-VIS no la sugiere.
  static const bannerDeBaja = 'Ubicación alternativa dada de baja';

  /// Regla de negocio: lo que muestra la persona cuando la referenciada se dio de baja.
  static const avisoDeBaja =
      'Ubicación alternativa dada de baja — actualizar antes de agendar cobranza';

  /// Escenario «sin otras ubicaciones registradas»: el estado vacío del selector.
  static const sinOtrasUbicaciones = 'Registrá otra ubicación para usarla como alternativa';
}
