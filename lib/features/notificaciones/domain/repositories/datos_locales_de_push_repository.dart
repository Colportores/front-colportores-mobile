/// Lo que el teléfono sabe para armar el texto de una push (HU-NOT-003: la push trae UUIDs y la app
/// los resuelve con su base local, offline-first). Cada lectura devuelve `null` (o 0) si todavía no
/// hay dato (la fila aún no bajó con el sync); lanza si no puede leer.
abstract interface class DatosLocalesDePushRepository {
  /// El nombre de la campaña [campaniaId], o `null` si no está en el teléfono.
  Future<String?> nombreDeCampania(String campaniaId);

  /// El nombre de la zona [zonaId], o `null` si no está en el teléfono.
  Future<String?> nombreDeZona(String zonaId);

  /// Cuántas visitas programadas hay para el día siguiente a [ahora] (día local).
  Future<int> visitasProgramadasParaManana(DateTime ahora);
}
