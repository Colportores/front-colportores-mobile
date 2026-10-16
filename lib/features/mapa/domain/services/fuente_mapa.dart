import 'package:equatable/equatable.dart';

import 'resolutores_mapa.dart';

/// De dónde sale el mapa que dibuja `MapaBase` (HU-UBI-003, ADR-011): uno o más archivos PMTiles
/// locales (el paquete descargado), remotos (el bucket público de Storage) o nada.
///
/// Un paquete puede venir en varias partes (una ciudad grande va en dos archivos, cada uno con su
/// zona): el estilo arma una fuente por parte, ver `ConstructorEstiloMapa`.
///
/// Con [FuenteTiles.sinTiles] el mapa es el color liso del diseño: no hay datos que dibujar, pero
/// los puntos y el radio de precisión se siguen viendo.
final class FuenteMapa extends Equatable {
  const FuenteMapa.sinTiles() : tipo = FuenteTiles.sinTiles, _unico = null, _varios = const [];

  /// El paquete descargado, en [ruta] dentro del almacenamiento interno de la app: MapLibre lo
  /// abre sin red. Tiene que ser una ruta absoluta de ese directorio, no del almacenamiento
  /// externo (la capa nativa no lo puede leer).
  const FuenteMapa.offline(String ruta)
    : tipo = FuenteTiles.pmtilesOffline,
      _unico = ruta,
      _varios = const [];

  /// El paquete descargado en varias partes: una ruta por parte, en el orden del catálogo.
  const FuenteMapa.offlineEnPartes(List<String> rutas)
    : tipo = FuenteTiles.pmtilesOffline,
      _unico = null,
      _varios = rutas;

  /// Un PMTiles servido por HTTP(S) con soporte de `Range` (el bucket `mapas` de Supabase
  /// Storage), en [url].
  const FuenteMapa.online(String url)
    : tipo = FuenteTiles.servidorOnline,
      _unico = url,
      _varios = const [];

  /// El paquete servido en varias partes: una URL por parte, en el orden del catálogo.
  const FuenteMapa.onlineEnPartes(List<String> urls)
    : tipo = FuenteTiles.servidorOnline,
      _unico = null,
      _varios = urls;

  final FuenteTiles tipo;

  // Un solo origen (el constructor `const` no puede armar una lista con un parámetro) o varios.
  final String? _unico;
  final List<String> _varios;

  /// Las partes en el orden del catálogo; vacío si no hay tiles.
  List<String> get origenes => [?_unico, ..._varios];

  /// Lo que va en `sources.protomaps.url` del estilo (la primera parte); `null` si no hay tiles.
  String? get urlPmtiles => urlsPmtiles.firstOrNull;

  /// Una URL `pmtiles://…` por parte, en el orden del catálogo.
  List<String> get urlsPmtiles => switch (tipo) {
    FuenteTiles.pmtilesOffline => [for (final ruta in origenes) 'pmtiles://file://$ruta'],
    FuenteTiles.servidorOnline => [for (final url in origenes) 'pmtiles://$url'],
    FuenteTiles.sinTiles => const [],
  };

  bool get hayTiles => tipo != FuenteTiles.sinTiles;

  /// Elige la fuente con [ResolutorFuenteTiles]: el paquete descargado ([rutasOffline], una por
  /// parte) si lo hay; si no, el PMTiles online ([urlsOnline]) si hay red y el servidor responde;
  /// si no, sin tiles. Sin [urlsOnline] no hay servidor al cual ir, haya red o no.
  static FuenteMapa resolver({
    List<String> rutasOffline = const [],
    List<String> urlsOnline = const [],
    required bool hayRed,
    bool servidorOnlineDisponible = true,
  }) {
    final tipo = ResolutorFuenteTiles.resolver(
      hayPaqueteOffline: rutasOffline.isNotEmpty,
      hayRed: hayRed && urlsOnline.isNotEmpty,
      servidorOnlineDisponible: servidorOnlineDisponible,
    );
    return switch (tipo) {
      FuenteTiles.pmtilesOffline => FuenteMapa.offlineEnPartes(List.unmodifiable(rutasOffline)),
      FuenteTiles.servidorOnline => FuenteMapa.onlineEnPartes(List.unmodifiable(urlsOnline)),
      FuenteTiles.sinTiles => const FuenteMapa.sinTiles(),
    };
  }

  @override
  List<Object?> get props => [tipo, origenes];
}
