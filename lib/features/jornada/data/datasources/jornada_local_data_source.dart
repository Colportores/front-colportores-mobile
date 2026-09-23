import '../models/jornada_model.dart';

/// Persistencia local de las jornadas.
///
/// La implementación real es `JornadaLocalDataSourceDrift`, sobre la tabla `jornada` de la DB
/// cifrada (Drift + SQLCipher). `JornadaLocalDataSourceEnMemoria` cumple el mismo contrato sin
/// infraestructura, para tests y para desarrollar la UI.
abstract interface class JornadaLocalDataSource {
  /// La jornada abierta del colportor (sin `fin` y sin soft delete), o `null`.
  Future<JornadaModel?> obtenerActiva(String colportorId);

  /// Inserta una jornada nueva.
  ///
  /// Lanza [JornadaActivaExistenteException] si el colportor ya tiene una jornada abierta. La
  /// comprobación y la inserción tienen que ser atómicas (en la DB: transacción o índice único
  /// parcial), porque es lo que sostiene "una sola jornada activa" frente a dos inicios casi
  /// simultáneos.
  Future<void> insertar(JornadaModel jornada);

  /// Guarda el cierre de [jornada] (HU-JOR-002): escribe solo su `fin` y su `updated_at`.
  ///
  /// Lanza [JornadaNoAbiertaException] si la jornada no existe o ya no está abierta (tiene `fin`
  /// o soft delete). Comprobar y escribir tiene que ser atómico, para que dos toques seguidos en
  /// "Finalizar jornada" no pisen el `fin` del primero.
  Future<void> finalizar(JornadaModel jornada);
}

/// La jornada que se quiso cerrar ya no está abierta; el repositorio la traduce a
/// `FailureSinJornadaActiva`.
final class JornadaNoAbiertaException implements Exception {
  const JornadaNoAbiertaException();

  @override
  String toString() => 'JornadaNoAbiertaException';
}

/// El colportor ya tiene una jornada abierta; el repositorio la traduce a `FailureJornadaActiva`.
final class JornadaActivaExistenteException implements Exception {
  const JornadaActivaExistenteException();

  @override
  String toString() => 'JornadaActivaExistenteException';
}
