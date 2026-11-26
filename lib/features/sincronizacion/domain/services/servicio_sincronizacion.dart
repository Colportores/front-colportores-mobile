import '../entities/estado_sincronizacion.dart';

/// Lo que la pantalla de sincronización (vista 25) le pide al motor de sync (HU-SYNC-007 y
/// HU-SYNC-008). La implementación es [ServicioSincronizacionMotor]; los tests de las pantallas usan
/// una en memoria.
abstract interface class ServicioSincronizacion {
  /// El estado de ahora.
  Future<EstadoSincronizacion> estado();

  /// Cada cambio del estado mientras alguien escucha.
  Stream<EstadoSincronizacion> get cambios;

  /// «Actualizar ahora»: sube lo pendiente y baja lo del coordinador en el momento, también con el
  /// modo ahorro y con datos móviles. No lanza: si el servidor no contesta devuelve
  /// [ActualizacionFallida].
  Future<ResultadoActualizacion> actualizarAhora();

  /// Las operaciones que el servidor rechazó, de la más nueva a la más vieja.
  Future<List<OperacionFallida>> operacionesFallidas();

  /// Devuelve a la cola las operaciones rechazadas (todas, o la de [id]). No dispara el envío: sigue
  /// [actualizarAhora]. Devuelve cuántas reencoló.
  Future<int> reintentarFallidas({String? id});

  /// Le dice al motor si el modo ahorro está activo (HU-SYNC-008).
  void aplicarModoAhorro({required bool activo});
}
