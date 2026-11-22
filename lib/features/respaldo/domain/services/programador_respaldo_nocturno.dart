/// Quien le pide al sistema que despierte la app de noche para respaldar (HU-SYNC-005, ADR-009:
/// `workmanager` en Android y `BGTaskScheduler` en iOS). Puerto: el dominio no conoce el plugin.
///
/// Las dos operaciones son idempotentes y **no lanzan**: programar dos veces deja una sola tarea, y
/// cancelar sin tarea no hace nada. Una falla del sistema no puede frenar a quien las llama (conectar
/// Drive, abrir la app): se anota y el respaldo del cierre de jornada y el de la vuelta a la app
/// (R30) siguen cubriendo.
abstract interface class ProgramadorDeRespaldoNocturno {
  /// Deja programado el respaldo de la ventana nocturna: 03:00, con Wi-Fi y el teléfono cargando.
  Future<void> programar();

  /// Saca la tarea (se desconectó Drive o se cerró la sesión): no hay qué respaldar de noche.
  Future<void> cancelar();
}

/// Sin segundo plano (tests, escritorio): no programa nada.
final class ProgramadorSinSegundoPlano implements ProgramadorDeRespaldoNocturno {
  const ProgramadorSinSegundoPlano();

  @override
  Future<void> programar() async {}

  @override
  Future<void> cancelar() async {}
}
