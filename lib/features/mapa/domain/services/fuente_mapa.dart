import 'package:equatable/equatable.dart';

import 'resolutores_mapa.dart';

/// De dónde sale el mapa que dibuja `MapaBase` (HU-UBI-003, ADR-011): un archivo PMTiles local
/// (el paquete descargado), uno remoto (el bucket público de Storage) o nada.
///
/// Con [FuenteTiles.sinTiles] el mapa es el color liso del diseño: no hay datos que dibujar, pero
/// los puntos y el radio de precisión se siguen viendo.
final class FuenteMapa extends Equatable {
  const FuenteMapa.sinTiles() : tipo = FuenteTiles.sinTiles, _origen = null;

  /// El paquete descargado, en [ruta] dentro del almacenamiento interno de la app: MapLibre lo
  /// abre sin red. Tiene que ser una ruta absoluta de ese directorio, no del almacenamiento
  /// externo (la capa nativa no lo puede leer).
  const FuenteMapa.offline(String ruta) : tipo = FuenteTiles.pmtilesOffline, _origen = ruta;

  /// Un PMTiles servido por HTTP(S) con soporte de `Range` (el bucket `mapas` de Supabase
  /// Storage), en [url].
  const FuenteMapa.online(String url) : tipo = FuenteTiles.servidorOnline, _origen = url;

  final FuenteTiles tipo;
  final String? _origen;

  /// Lo que va en `sources.protomaps.url` del estilo; `null` si no hay tiles.
  String? get urlPmtiles => switch (tipo) {
    FuenteTiles.pmtilesOffline => 'pmtiles://file://$_origen',
    FuenteTiles.servidorOnline => 'pmtiles://$_origen',
    FuenteTiles.sinTiles => null,
  };

  bool get hayTiles => tipo != FuenteTiles.sinTiles;

  /// Elige la fuente con [ResolutorFuenteTiles]: el paquete descargado ([rutaOffline]) si lo hay;
  /// si no, el PMTiles online ([urlOnline]) si hay red y el servidor responde; si no, sin tiles.
  /// Sin [urlOnline] no hay servidor al cual ir, haya red o no.
  static FuenteMapa resolver({
    String? rutaOffline,
    String? urlOnline,
    required bool hayRed,
    bool servidorOnlineDisponible = true,
  }) {
    final tipo = ResolutorFuenteTiles.resolver(
      hayPaqueteOffline: rutaOffline != null,
      hayRed: hayRed && urlOnline != null,
      servidorOnlineDisponible: servidorOnlineDisponible,
    );
    return switch (tipo) {
      FuenteTiles.pmtilesOffline => FuenteMapa.offline(rutaOffline!),
      FuenteTiles.servidorOnline => FuenteMapa.online(urlOnline!),
      FuenteTiles.sinTiles => const FuenteMapa.sinTiles(),
    };
  }

  @override
  List<Object?> get props => [tipo, _origen];
}
