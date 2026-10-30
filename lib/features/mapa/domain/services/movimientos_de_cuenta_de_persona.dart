import '../entities/ficha_de_persona.dart';

/// De dónde salen las entregas y los cobros de una persona (el historial de la ficha, vista 32B).
///
/// Lo cubre el adaptador de la DB local (`MovimientosDeCuentaDrift`): emite [EntregaEnFicha] y
/// [CobroEnFicha] y la ficha los mezcla por fecha con las visitas y las ventas.
abstract interface class MovimientosDeCuentaDeLaPersona {
  /// Las entregas y los cobros de [personaId] (de todos sus vínculos), al día cuando cambian. Un error
  /// de lectura sale por el `Stream`: la ficha no da por hecho que no hay nada.
  Stream<List<MovimientoDeFicha>> observar(String personaId);
}
