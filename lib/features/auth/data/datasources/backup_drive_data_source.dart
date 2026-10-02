/// El backup cifrado en Google Drive (`appDataFolder`, ADR-006), visto desde el borrado de datos
/// locales (HU-AUTH-010).
///
/// El respaldo en Drive se mantiene (decisión de Cristian, 02/10: lo que se sacó fue el login con
/// Google, no el respaldo). Llega con #184 (OAuth de Drive, HU-SYNC-004) y #185 (backup,
/// HU-SYNC-005): hasta entonces la implementación es [BackupDriveNoDisponible].
abstract interface class BackupDriveDataSource {
  /// Si hay un backup de este usuario en Drive.
  Future<bool> existe();

  /// Borra todo el contenido de `appDataFolder`. Lanza `SinConexionException` sin red y cualquier
  /// otra excepción si Drive falla.
  Future<void> borrar();
}

/// Mientras no exista el backup en Drive (#184 y #185) no hay nada que ofrecer ni que borrar: la
/// pantalla de borrado no muestra la opción (un botón que no hace nada sería un callejón). La
/// falla de Drive (19A·07) y la opción de Drive de la confirmación (19A·09) ya están programadas
/// y probadas: se activan solas cuando [existe] devuelva `true`.
final class BackupDriveNoDisponible implements BackupDriveDataSource {
  const BackupDriveNoDisponible();

  @override
  Future<bool> existe() async => false;

  @override
  Future<void> borrar() async {}
}
