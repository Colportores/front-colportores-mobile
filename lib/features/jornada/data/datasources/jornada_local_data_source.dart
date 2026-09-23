import '../models/jornada_model.dart';

/// Persistencia local de las jornadas.
///
/// La implementación real es la tabla `jornada` en la DB cifrada (Drift + SQLCipher), que
/// todavía no existe: la primera tabla de negocio espera la decisión de tooling de codegen
/// (`drift_dev` vs `custom_lint`, issue #6 y la nota del `pubspec.yaml`). Hasta entonces,
/// [JornadaLocalDataSourceEnMemoria] cumple este contrato.
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
}

/// El colportor ya tiene una jornada abierta; el repositorio la traduce a `FailureJornadaActiva`.
final class JornadaActivaExistenteException implements Exception {
  const JornadaActivaExistenteException();

  @override
  String toString() => 'JornadaActivaExistenteException';
}
