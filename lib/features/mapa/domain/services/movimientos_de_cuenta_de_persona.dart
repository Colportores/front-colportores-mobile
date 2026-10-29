import '../entities/ficha_de_persona.dart';

/// De dónde salen las entregas y los cobros de una persona (el historial de la ficha, vista 32B).
///
/// **Sin adaptador todavía**: las tablas locales de entregas y cobros llegan con HU-VEN-002/003 y
/// HU-COB-001, así que hasta entonces el puerto lo cubre [MovimientosDeCuentaSinFuente] y la ficha
/// muestra solo visitas y ventas. Cuando lleguen, el adaptador emite [EntregaEnFicha] y
/// [CobroEnFicha] y la ficha los mezcla por fecha sin cambiar nada más.
abstract interface class MovimientosDeCuentaDeLaPersona {
  /// Las entregas y los cobros de [personaId] (de todos sus vínculos), al día cuando cambian. Un error
  /// de lectura sale por el `Stream`: la ficha no da por hecho que no hay nada.
  Stream<List<MovimientoDeFicha>> observar(String personaId);
}

/// Mientras no haya de dónde sacarlos: no se sabe de nadie.
final class MovimientosDeCuentaSinFuente implements MovimientosDeCuentaDeLaPersona {
  const MovimientosDeCuentaSinFuente();

  @override
  Stream<List<MovimientoDeFicha>> observar(String personaId) =>
      Stream.value(const <MovimientoDeFicha>[]);
}
