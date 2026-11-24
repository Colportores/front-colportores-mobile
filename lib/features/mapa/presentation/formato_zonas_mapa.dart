import '../domain/entities/zona_del_mapa.dart';

/// Los textos de las zonas sobre el mapa de ubicaciones (HU-UBI-003, #511). El canvas no los dibuja
/// (la decisión de Cristian del 27/10, «Zonas mapa», es no esperar diseño): son propuestas marcadas
/// «mapa §2: texto» en el PR, todas en este archivo.
abstract final class TextosMapaZonas {
  /// El nombre de la zona propia sobre el mapa: no depende solo del color ni del grosor del borde.
  static String rotuloPropia(String nombre) => 'Tu zona · $nombre';

  /// Lo que le suma al nodo «Mapa de ubicaciones» para el lector de pantalla; `null` sin zonas
  /// propias. Nombra solo las zonas propias (#654): las de otros colportores no se mencionan.
  static String? paraElLector(List<ZonaDelMapa> zonas) {
    final propias = [
      for (final z in zonas)
        if (z.propia) z.nombre,
    ];
    if (propias.isEmpty) return null;
    return 'Tu zona: ${_unir(propias)}.';
  }

  static String _unir(List<String> nombres) {
    if (nombres.length == 1) return nombres.single;
    return '${nombres.take(nombres.length - 1).join(', ')} y ${nombres.last}';
  }
}
