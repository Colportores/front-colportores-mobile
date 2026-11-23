import '../../domain/entities/campania_inscripta.dart';

/// De dónde salen las campañas en las que el colportor tiene una inscripción viva, con su nombre,
/// sus fechas y la zona asignada (HU-AUTH-008: el aviso de la campaña por empezar y «Ya te
/// asignaron»). La fuente es el pull de catálogos (`campania_colportor`, `campania`, `zona`,
/// `campania_ciudad` y `ciudad`): lee solo del teléfono, sin red. El adaptador sobre las réplicas es
/// `CampaniasInscriptasLocal`.
abstract interface class CampaniasInscriptasDataSource {
  /// Las campañas de [usuarioId] con inscripción viva y sin baja, cada vez que la réplica cambia:
  /// emite el estado actual al suscribirse y uno nuevo cuando un pull termina de escribir. Incluye las
  /// que ya terminaron (quien decide qué cuenta hoy es `SituacionDeCampania`).
  ///
  /// Emite `null` cuando el teléfono **todavía no puede saberlo**: una inscripción apunta a una
  /// campaña que todavía no llegó a la réplica. Una lista vacía quiere decir «se leyó y no hay». Con
  /// `null` la app no frena nada ni afirma nada de la campaña.
  ///
  /// No lanza al suscribirse: una lectura que falla se reporta como error del *stream*.
  Stream<List<CampaniaInscripta>?> observar(String usuarioId);
}
