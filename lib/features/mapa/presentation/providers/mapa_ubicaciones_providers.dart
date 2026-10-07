import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../tiles/domain/entities/paquete_tiles.dart' show AmbitoTrabajo;

// Cableado del mapa de ubicaciones (vista 06, HU-UBI-003). Usa la lista del colportor y el aviso del
// mapa que ya existen (`lista_ubicaciones_providers`, `situacion_mapa_providers`); lo único propio
// es de qué ciudad es el mapa.

/// De qué ciudad (o zona) es el mapa de la vista 06: de ahí salen el mapa descargado y el aviso.
///
/// **Dormido**: la ciudad del colportor todavía no tiene fuente (#274, las ciudades de su campaña) y
/// la zona es solo visual, así que es un ámbito sin ciudad. Mientras sea así, el aviso de la vista
/// no ofrece «Descargar mapa» (decisión de Cristian del 06/10 en el #199: no hay dónde elegir la
/// ciudad). Cuando #274 la sepa, solo cambia este provider y la descarga aparece sola.
final ambitoMapaUbicacionesProvider = Provider<AmbitoTrabajo>((ref) => const AmbitoTrabajo());
