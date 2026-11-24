/// Si el colportor activó el modo ahorro de datos (HU-SYNC-008): un interruptor global en
/// Configuración que sobrevive a cerrar la app y se borra con el borrado de datos locales
/// (HU-AUTH-010).
abstract interface class ModoAhorroRepository {
  /// Lo último que se guardó; sin nada guardado (o si el almacén no se deja leer) está apagado:
  /// el comportamiento estándar.
  Future<bool> leer();

  /// Guarda [activo]. Lanza si no se pudo: quien lo llama no debe mostrar el modo como cambiado si
  /// no quedó guardado (después de reiniciar la app volvería al valor viejo sin avisar).
  Future<void> guardar({required bool activo});
}
