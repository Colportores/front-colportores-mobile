import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/fuente_mapa.dart';
import '../mapa_base/modelo_mapa_base.dart';
import '../mapa_base/vista_maplibre.dart';

/// De dónde salen los tiles del mapa de fondo (HU-UBI-003, ADR-011): el paquete PMTiles descargado
/// (offline, el priorizado), el PMTiles del bucket de Storage (online) o nada.
///
/// El paquete descargado (`ObservarPaqueteOfflineUseCase`, #198), la lectura de `catalogo.json` y
/// la conectividad todavía no tienen provider (llegan con #189 y #199), así que hasta entonces no
/// hay fondo y las vistas avisan «Sin tiles para esta zona. Descargá tu ciudad en Configuración.».
/// Cuando lleguen, este provider se arma con `FuenteMapa.resolver(rutaOffline: …, urlOnline: …,
/// hayRed: …)`, que usa `ResolutorFuenteTiles`.
final fuenteMapaProvider = Provider<FuenteMapa>((ref) => const FuenteMapa.sinTiles());

/// La vista nativa de `MapaBase`: MapLibre. Los tests de widgets la reemplazan por una falsa (la
/// vista nativa no se dibuja en `flutter test`).
final constructorVistaMapaProvider = Provider<ConstructorVistaMapa>(
  (ref) => construirVistaMapLibre,
);
