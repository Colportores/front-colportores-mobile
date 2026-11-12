import 'dart:math' as math;

import '../value_objects/coordenadas.dart';
import 'proyeccion_mercator.dart';

/// Qué ubicaciones hay «en el mismo punto» al tocar una del mapa (vista 39, E·06 «3 ubicaciones
/// acá» / «Elegí cuál»).
///
/// La regla es la decisión del orquestador del 23/10 (mapa §2, aplicando «Números casas» de Cristian,
/// «debería de arreglarse haciendo zoom con los dedos»): **sin un número nuevo**. Un toque abre la
/// ubicación más cercana dentro de 44 dp (M·02). La elección de E·06 sale solo cuando hay **más de
/// una** de las que pinta el mapa dentro de esos 44 dp **y el mapa ya está en su zoom máximo**:
/// acercar más ya no las separa. Antes del zoom máximo el toque abre la más cercana, y la persona
/// acerca con los dedos. La lista va de la más cercana al toque a la más lejana.
abstract final class UbicacionesEnElPunto {
  /// El radio del toque (M·02), en dp: el mismo de `SeleccionToque.radioDeCuadradosDp`.
  static const radioDp = 44.0;

  /// Cuánto puede faltar para el zoom máximo y contar como «en el zoom máximo» (el zoom de MapLibre
  /// no vuelve exacto después de un gesto).
  static const toleranciaDeZoom = 0.05;

  /// Los `id` de las ubicaciones de [todas] que están a [radioDp] dp o menos de [tocada] con el zoom
  /// [zoom], de la más cercana a la más lejana (la tocada va primera). Vacía si no hay más de una, si
  /// el mapa no está en su zoom máximo ([zoomMaximo]) o si [tocada] no está en [todas].
  static List<String> elegibles({
    required String tocada,
    required Iterable<({String id, Coordenadas coordenadas})> todas,
    required double zoom,
    required double zoomMaximo,
  }) {
    if (!zoom.isFinite || zoom < zoomMaximo - toleranciaDeZoom) return const [];
    ({String id, Coordenadas coordenadas})? origen;
    for (final u in todas) {
      if (u.id == tocada) origen = u;
    }
    if (origen == null) return const [];
    final centro = ProyeccionMercator.aPixeles(origen.coordenadas, zoom);
    final cercanas = <({String id, double distancia, int orden})>[];
    var orden = 0;
    for (final u in todas) {
      final p = ProyeccionMercator.aPixeles(u.coordenadas, zoom);
      final distancia = math.sqrt(math.pow(p.x - centro.x, 2) + math.pow(p.y - centro.y, 2));
      if (distancia <= radioDp) cercanas.add((id: u.id, distancia: distancia, orden: orden));
      orden++;
    }
    if (cercanas.length < 2) return const [];
    // La tocada va primera; a igual distancia (mismo punto) las demás en el orden en que llegaron (el
    // `sort` de Dart no es estable).
    cercanas.sort((a, b) {
      if (a.id == tocada) return b.id == tocada ? 0 : -1;
      if (b.id == tocada) return 1;
      final porDistancia = a.distancia.compareTo(b.distancia);
      return porDistancia != 0 ? porDistancia : a.orden.compareTo(b.orden);
    });
    return [for (final c in cercanas) c.id];
  }
}
