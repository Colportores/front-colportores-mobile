import 'dart:math' as math;

import '../entities/marcador_mapa.dart';
import '../value_objects/coordenadas.dart';

/// HU-UBI-003 — agrupa los marcadores que se superponen a un zoom dado (cluster automático).
///
/// Grilla en pantalla: el mundo mide `256 · 2^zoom` píxeles de ancho (proyección web, la de OSM),
/// y cada celda de [radioPxPorDefecto] píxeles de lado es un grupo. Es determinista (mismos
/// marcadores y zoom, mismos grupos y mismo orden), barato (O(n)) y no depende de ninguna
/// librería de mapa, así que sirve para los cientos de marcadores de RR-04/R19. La grilla se define
/// en grados de latitud sin corregir la proyección: cerca de los polos las celdas son más chicas
/// de lo que parece; a las latitudes de trabajo (Uruguay) no importa.
///
/// A un zoom en que ninguno se superpone, cada marcador queda en su grupo individual.
abstract final class AgrupadorMarcadores {
  /// Lado de la celda por defecto, en píxeles (un marcador mide ~40).
  static const radioPxPorDefecto = 60.0;

  static const zoomMinimo = 0.0;
  static const zoomMaximo = 22.0;

  static List<GrupoMarcadores> agrupar(
    Iterable<MarcadorMapa> marcadores, {
    required double zoom,
    double radioPx = radioPxPorDefecto,
  }) {
    final z = zoom.isNaN ? zoomMinimo : zoom.clamp(zoomMinimo, zoomMaximo);
    final px = radioPx.isFinite && radioPx > 0 ? radioPx : radioPxPorDefecto;
    final celda = px * 360 / (256 * math.pow(2, z));

    final celdas = <(int, int), List<MarcadorMapa>>{};
    for (final m in marcadores) {
      final clave = ((m.lat / celda).floor(), (m.lon / celda).floor());
      (celdas[clave] ??= []).add(m);
    }

    final claves = celdas.keys.toList()
      ..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    return [for (final clave in claves) _grupo(celdas[clave]!)];
  }

  static GrupoMarcadores _grupo(List<MarcadorMapa> ms) {
    ms.sort((a, b) => a.ubicacionId.compareTo(b.ubicacionId));
    final lat = ms.fold(0.0, (s, m) => s + m.lat) / ms.length;
    final lon = ms.fold(0.0, (s, m) => s + m.lon) / ms.length;
    return GrupoMarcadores(
      marcadores: List.unmodifiable(ms),
      centro: Coordenadas(lat: lat, lon: lon),
    );
  }
}
