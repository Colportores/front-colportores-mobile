import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/fuente_mapa.dart';
import '../mapa_base/modelo_mapa_base.dart';
import '../mapa_base/vista_maplibre.dart';

/// De dónde salen los tiles del mapa de fondo (HU-UBI-003, ADR-011): el paquete PMTiles descargado
/// (offline, el priorizado), el PMTiles del bucket de Storage (online) o nada.
///
/// El paquete descargado, el catálogo y la conectividad ya tienen provider (`tiles_providers.dart`
/// y `conectividad_providers.dart`, #189), pero este todavía no los usa: hasta que se conecte
/// (#190) no hay fondo y las vistas avisan «Sin tiles para esta zona. Descargá tu ciudad en
/// Configuración.». Se va a armar con `FuenteMapa.resolver(rutasOffline: …, urlsOnline: …,
/// hayRed: …)`, que usa `ResolutorFuenteTiles`.
final fuenteMapaProvider = Provider<FuenteMapa>((ref) => const FuenteMapa.sinTiles());

/// La vista nativa de `MapaBase`: MapLibre. Los tests de widgets la reemplazan por una falsa (la
/// vista nativa no se dibuja en `flutter test`).
final constructorVistaMapaProvider = Provider<ConstructorVistaMapa>(
  (ref) => construirVistaMapLibre,
);
