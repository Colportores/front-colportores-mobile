import 'dart:math' as math;

import '../value_objects/coordenadas.dart';

/// Un círculo sobre la superficie de la Tierra, de radio en metros, como polígono.
///
/// MapLibre dibuja los círculos con radio en píxeles; el radio de precisión del GPS es en metros
/// y tiene que crecer o achicarse con el zoom, así que se dibuja como polígono.
abstract final class CirculoGeografico {
  /// El anillo cerrado (el último vértice repite al primero) de [lados] lados alrededor de
  /// [centro], recorrido en sentido horario desde el norte. Vacío si [radioMetros] no es un número
  /// finito mayor que cero, o si [centro] no es un punto válido: no hay nada que dibujar.
  static List<Coordenadas> anillo(Coordenadas centro, double radioMetros, {int lados = 64}) {
    if (!radioMetros.isFinite || radioMetros <= 0) return const [];
    if (!centro.lat.isFinite || !centro.lon.isFinite || !centro.estanEnRango) return const [];
    final lat = centro.lat * math.pi / 180;
    final lon = centro.lon * math.pi / 180;
    final distancia = radioMetros / Coordenadas.radioTierraMetros;
    final vertices = <Coordenadas>[];
    for (var i = 0; i < lados; i++) {
      final rumbo = 2 * math.pi * i / lados;
      final latDestino = math.asin(
        math.sin(lat) * math.cos(distancia) + math.cos(lat) * math.sin(distancia) * math.cos(rumbo),
      );
      final lonDestino =
          lon +
          math.atan2(
            math.sin(rumbo) * math.sin(distancia) * math.cos(lat),
            math.cos(distancia) - math.sin(lat) * math.sin(latDestino),
          );
      vertices.add(
        Coordenadas(lat: latDestino * 180 / math.pi, lon: _normalizar(lonDestino * 180 / math.pi)),
      );
    }
    return [...vertices, vertices.first];
  }

  static double _normalizar(double lon) => ((lon + 180) % 360 + 360) % 360 - 180;
}
