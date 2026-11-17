/// Los textos de las casas «fuera del área» en el mapa (#713; HU-SYNC-011, R-UB12). Ningún artboard
/// los dibuja: los propone el implementador con el tono de los avisos del mapa (qué pasa y qué hacer),
/// por el criterio del 10/11 (huecos chicos de diseño sin revisión de Cristian).
abstract final class TextosFueraDelArea {
  /// La etiqueta de la fila y de la hoja de la casa.
  static const etiqueta = 'FUERA DE TU ÁREA';

  /// Lo que dice el lector de pantalla de la etiqueta.
  static const etiquetaLector = 'Fuera de tu área';

  /// La fila de «Referencias» que explica la marca (el aro ámbar).
  static const leyenda = 'Fuera de tu área: ya no es de tu zona. No se borra.';

  /// El interruptor de «Referencias».
  static const mostrar = 'Mostrar las casas fuera de tu área';

  /// «Ver» del aviso de las ocultas.
  static const ver = 'Ver';

  /// Lo que se anuncia al cambiar la elección.
  static const anuncioVisibles = 'Las casas fuera de tu área se ven en el mapa.';
  static const anuncioOcultas = 'Las casas fuera de tu área quedaron ocultas.';
}

/// Lo que el mapa escribe con la cantidad de casas fuera del área.
abstract final class FormatoFueraDelArea {
  /// «1 casa» / «3 casas».
  static String casas(int n) => n == 1 ? '1 casa' : '$n casas';

  /// El aviso del mapa con las casas ocultas: «3 casas fuera de tu área ocultas».
  static String ocultas(int n) =>
      n == 1 ? '1 casa fuera de tu área oculta' : '$n casas fuera de tu área ocultas';

  /// Lo que lee el lector del aviso de las ocultas, con su acción.
  static String ocultasLector(int n) => '${ocultas(n)}. ${TextosFueraDelArea.ver}';

  /// El detalle del interruptor de «Referencias»: cuántas son y que ocultarlas no borra nada.
  static String detalleInterruptor(int n) =>
      '${casas(n)}. Ocultarlas solo cambia lo que ves en el mapa: no se borra nada.';

  /// Lo que el mapa le suma a su nombre para el lector de pantalla (`null` si no hay ninguna).
  static String? paraElLector(int cantidad, {required bool ver}) {
    if (cantidad == 0) return null;
    if (!ver) return ocultas(cantidad);
    return cantidad == 1
        ? '1 casa fuera de tu área, con un aro ámbar'
        : '$cantidad casas fuera de tu área, con un aro ámbar';
  }
}
