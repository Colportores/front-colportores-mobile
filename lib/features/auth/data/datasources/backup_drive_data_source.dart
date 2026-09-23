/// El backup cifrado en Google Drive (`appDataFolder`, ADR-006), visto desde el borrado de datos
/// locales (HU-AUTH-010).
///
/// El backup llega con HU-SYNC: hasta entonces la implementación es [BackupDriveNoDisponible].
abstract interface class BackupDriveDataSource {
  /// Si hay un backup de este usuario en Drive.
  Future<bool> existe();

  /// Borra todo el contenido de `appDataFolder`. Lanza `SinConexionException` sin red y cualquier
  /// otra excepción si Drive falla.
  Future<void> borrar();
}

/// Mientras no exista el backup en Drive (HU-SYNC) no hay nada que ofrecer ni que borrar: la
/// pantalla de borrado no muestra la opción.
final class BackupDriveNoDisponible implements BackupDriveDataSource {
  const BackupDriveNoDisponible();

  @override
  Future<bool> existe() async => false;

  @override
  Future<void> borrar() async {}
}
