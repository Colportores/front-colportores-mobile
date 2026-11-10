import '../value_objects/coordenadas.dart';
import '../value_objects/geometria_zona.dart';

/// Dónde poner el nombre de una zona sobre el mapa (#511): un punto **adentro** de la zona, aunque
/// tenga forma de L o de P (el centro del recuadro de una L cae afuera).
///
/// Se toma el polígono más grande (por su recuadro) y, sobre una línea horizontal por el medio de su
/// altura, el tramo de adentro más largo: su punto medio. Si por el medio no pasa ningún tramo
/// (borde degenerado), se prueba con otras alturas.
abstract final class PuntoRotuloDeZona {
  /// Las alturas del recuadro que se prueban, de la del medio hacia los costados.
  static const _fracciones = [.5, .4, .6, .3, .7, .2, .8, .1, .9];

  /// El punto del nombre de [geometria], o `null` si no se encuentra ninguno (una forma sin área).
  static Coordenadas? de(GeometriaZona geometria) {
    List<List<Coordenadas>>? mayor;
    var areaMayor = -1.0;
    for (final poligono in geometria.poligonos) {
      final recuadro = _Recuadro.de(poligono.first);
      if (recuadro.area > areaMayor) {
        areaMayor = recuadro.area;
        mayor = poligono;
      }
    }
    if (mayor == null) return null;
    final recuadro = _Recuadro.de(mayor.first);
    for (final fraccion in _fracciones) {
      final lat = recuadro.sur + (recuadro.norte - recuadro.sur) * fraccion;
      final punto = _tramoMasLargo(mayor, lat);
      if (punto != null) return punto;
    }
    return null;
  }

  /// El punto medio del tramo de adentro más largo de la línea de latitud [lat] (par-impar entre
  /// todos los anillos: los huecos quedan afuera).
  static Coordenadas? _tramoMasLargo(List<List<Coordenadas>> anillos, double lat) {
    final cortes = <double>[];
    for (final anillo in anillos) {
      for (var i = 0; i < anillo.length - 1; i++) {
        final a = anillo[i];
        final b = anillo[i + 1];
        if ((a.lat <= lat) == (b.lat <= lat)) continue;
        cortes.add(a.lon + (lat - a.lat) * (b.lon - a.lon) / (b.lat - a.lat));
      }
    }
    cortes.sort();
    double? mejorAncho;
    double? mejorMedio;
    for (var i = 0; i + 1 < cortes.length; i += 2) {
      final ancho = cortes[i + 1] - cortes[i];
      if (ancho > (mejorAncho ?? 0)) {
        mejorAncho = ancho;
        mejorMedio = (cortes[i] + cortes[i + 1]) / 2;
      }
    }
    return mejorMedio == null ? null : Coordenadas(lat: lat, lon: mejorMedio);
  }
}

class _Recuadro {
  const _Recuadro(this.sur, this.norte, this.oeste, this.este);

  factory _Recuadro.de(List<Coordenadas> anillo) {
    var sur = anillo.first.lat;
    var norte = sur;
    var oeste = anillo.first.lon;
    var este = oeste;
    for (final p in anillo) {
      if (p.lat < sur) sur = p.lat;
      if (p.lat > norte) norte = p.lat;
      if (p.lon < oeste) oeste = p.lon;
      if (p.lon > este) este = p.lon;
    }
    return _Recuadro(sur, norte, oeste, este);
  }

  final double sur;
  final double norte;
  final double oeste;
  final double este;

  double get area => (norte - sur) * (este - oeste);
}
