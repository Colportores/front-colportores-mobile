import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../tiles/domain/entities/paquete_tiles.dart' show AmbitoTrabajo;
import '../../domain/services/fuente_mapa.dart';
import '../mapa_base/modelo_mapa_base.dart';
import '../mapa_base/vista_maplibre.dart';
import 'situacion_mapa_providers.dart';

/// De dónde salen los tiles del mapa de fondo de [AmbitoTrabajo] (HU-UBI-003, ADR-011): el paquete
/// PMTiles descargado (offline, el priorizado), el PMTiles del bucket de Storage (online) o nada.
final fuenteMapaProvider = Provider.autoDispose.family<FuenteMapa, AmbitoTrabajo>(
  (ref, ambito) => ref.watch(situacionMapaProvider(ambito).select((situacion) => situacion.fuente)),
);

/// La vista nativa de `MapaBase`: MapLibre. Los tests de widgets la reemplazan por una falsa (la
/// vista nativa no se dibuja en `flutter test`).
final constructorVistaMapaProvider = Provider<ConstructorVistaMapa>(
  (ref) => construirVistaMapLibre,
);
