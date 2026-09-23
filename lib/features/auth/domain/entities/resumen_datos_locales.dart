import 'package:equatable/equatable.dart';

/// Lo que hay guardado en este teléfono, para el resumen previo al borrado (HU-AUTH-010) y la
/// advertencia previa al cierre de sesión (HU-AUTH-006). Solo cantidades: nunca datos de clientes.
final class ResumenDatosLocales extends Equatable {
  const ResumenDatosLocales({
    required this.personas,
    required this.visitas,
    required this.operacionesSinSincronizar,
    required this.hayBackupEnDrive,
  });

  /// Personas registradas localmente.
  final int personas;

  /// Visitas registradas localmente.
  final int visitas;

  /// Cambios que todavía no se subieron al servidor: borrar los pierde (HU-AUTH-010: "las
  /// operaciones encoladas no se subirán"). `null` si no se pudo contar (la DB existe pero no se
  /// puede leer): el borrado sigue siendo posible, avisando que no se sabe cuánto se pierde.
  final int? operacionesSinSincronizar;

  /// Si existe un backup en Drive (`appDataFolder`) que el borrado podría incluir.
  final bool hayBackupEnDrive;

  @override
  List<Object?> get props => [personas, visitas, operacionesSinSincronizar, hayBackupEnDrive];
}

/// Cómo terminó un borrado de datos locales que llegó a borrar lo del teléfono (HU-AUTH-010).
/// Los datos locales **nunca** se restauran por una falla en Drive.
enum ResultadoBorradoDatosLocales {
  /// Se borró todo lo pedido.
  completo,

  /// Se borraron los datos locales, pero Drive no respondió por falta de red.
  backupDriveNoBorradoSinConexion,

  /// Se borraron los datos locales, pero Drive falló por otro motivo.
  backupDriveNoBorrado,
}
