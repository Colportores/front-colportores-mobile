/// Puerto para pedir el backup automático al cerrar la jornada (HU-JOR-002 → HU-SYNC-005).
///
/// Interfaz de dominio (ADR-009): el backup es del carril de sync (HU-SYNC-005) y todavía no está
/// implementado, así que el cierre de jornada solo lo **pide** a través de este puerto. La
/// implementación es la que decide si corre ahora: HU-JOR-002 lo condiciona a que haya Wi-Fi y
/// batería ≥ 30 %, y esas condiciones las conoce el motor de backup, no el caso de uso.
abstract interface class DisparadorBackup {
  /// Pide el backup después de cerrar la jornada de [colportorId].
  ///
  /// Vuelve enseguida: el backup corre aparte y no bloquea la pantalla. Si no se cumplen las
  /// condiciones (sin Wi-Fi, batería baja) la implementación lo deja para la próxima ventana; el
  /// cierre de la jornada ya quedó guardado igual.
  Future<void> solicitar(String colportorId);
}
