import 'dart:math' as math;

import '../value_objects/area_mapa.dart';
import '../value_objects/camara_mapa.dart';
import '../value_objects/coordenadas.dart';

/// La proyección Web Mercator con la escala de MapLibre (teselas de 512 px: a zoom `z` el mundo
/// mide `512 · 2^z` píxeles). Sirve para saber, sin preguntarle a la vista nativa, cuánto es un
/// movimiento en píxeles, qué área cubre el mapa y qué cámara deja un conjunto de puntos a la vista.
///
/// Los píxeles son los lógicos de Flutter (independientes de la densidad), los mismos con que
/// MapLibre dimensiona sus teselas.
abstract final class ProyeccionMercator {
  static const tamanoTesela = 512.0;

  /// Más allá de esta latitud Mercator no representa el mapa (se estira al infinito).
  static const latitudMaxima = 85.0511287798066;

  /// Los niveles de zoom que separan esta escala de la de `flutter_map` (teselas de 256 px: el mundo
  /// mide `256 · 2^z`): `512 · 2^(z − 1) = 256 · 2^z`. Un zoom pensado para `flutter_map` se ve al
  /// doble de cerca en MapLibre si se usa tal cual; [zoomDeFlutterMap] lo traduce.
  static const nivelesSobreFlutterMap = 1.0;

  /// Lado del mundo, en píxeles, a [zoom].
  static double tamanoMundo(double zoom) => tamanoTesela * math.pow(2, zoom);

  /// El zoom de MapLibre que encuadra lo mismo que [zoomFlutterMap] en `flutter_map` (teselas de
  /// 256 px). Los zoom que vienen de #267 (el alta de ubicación se diseñó con `flutter_map`) pasan
  /// por acá: es el único lugar donde está esa equivalencia.
  static double zoomDeFlutterMap(double zoomFlutterMap) => zoomFlutterMap - nivelesSobreFlutterMap;

  /// Radio de la esfera de Web Mercator (WGS84, el eje mayor), en metros.
  static const radioTierraMetros = 6378137.0;

  /// Cuántos metros mide un píxel (lógico) a la latitud [lat] y a [zoom]. A zoom 17 son unos 0,49 m
  /// en Montevideo; cada nivel de zoom lo divide por dos.
  static double metrosPorPixel(double lat, double zoom) {
    final latitud = lat.clamp(-latitudMaxima, latitudMaxima);
    return 2 * math.pi * radioTierraMetros * math.cos(latitud * math.pi / 180) / tamanoMundo(zoom);
  }

  /// El punto en píxeles del mundo a [zoom]: `(0, 0)` es la esquina noroeste, `x` crece al este e
  /// `y` hacia el sur.
  static ({double x, double y}) aPixeles(Coordenadas punto, double zoom) {
    final mundo = tamanoMundo(zoom);
    final lat = punto.lat.clamp(-latitudMaxima, latitudMaxima);
    final seno = math.sin(lat * math.pi / 180);
    final x = (punto.lon + 180) / 360 * mundo;
    final y = (0.5 - math.log((1 + seno) / (1 - seno)) / (4 * math.pi)) * mundo;
    return (x: x, y: y);
  }

  /// Lo inverso de [aPixeles].
  static Coordenadas aCoordenadas(double x, double y, double zoom) {
    final mundo = tamanoMundo(zoom);
    final lon = x / mundo * 360 - 180;
    final n = math.pi - 2 * math.pi * y / mundo;
    final lat = 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
    return Coordenadas(lat: lat, lon: lon);
  }

  /// Cuántos píxeles separan a [a] de [b] a [zoom].
  static double distanciaPixeles(Coordenadas a, Coordenadas b, double zoom) {
    final pa = aPixeles(a, zoom);
    final pb = aPixeles(b, zoom);
    return math.sqrt(math.pow(pa.x - pb.x, 2) + math.pow(pa.y - pb.y, 2));
  }

  /// Dónde cae [punto] en una vista de [ancho] × [alto] píxeles con [camara], desde la esquina
  /// superior izquierda, con el rumbo de la cámara aplicado: con rumbo 0 es el desplazamiento Mercator
  /// de siempre, y con otro el mapa está girado alrededor del centro de la vista.
  static ({double x, double y}) aPantalla(
    Coordenadas punto,
    CamaraMapa camara, {
    required double ancho,
    required double alto,
  }) {
    final enMundo = aPixeles(punto, camara.zoom);
    final centro = aPixeles(camara.centro, camara.zoom);
    final giro = _girar(enMundo.x - centro.x, enMundo.y - centro.y, camara.rumbo);
    return (x: giro.x + ancho / 2, y: giro.y + alto / 2);
  }

  /// El centro que hay que darle a una cámara de [zoom] y [rumbo] para que [punto] caiga a
  /// ([desplazamientoX], [desplazamientoY]) píxeles del centro de la vista (en la pantalla: `y` hacia
  /// abajo). Con rumbo 0 es correr el centro lo contrario de ese desplazamiento; con otro, el
  /// desplazamiento gira con el mapa.
  static Coordenadas centroQueDejaEn(
    Coordenadas punto, {
    required double zoom,
    double rumbo = 0,
    double desplazamientoX = 0,
    double desplazamientoY = 0,
  }) {
    final enMundo = aPixeles(punto, zoom);
    final mundo = _girar(desplazamientoX, desplazamientoY, -rumbo);
    return aCoordenadas(enMundo.x - mundo.x, enMundo.y - mundo.y, zoom);
  }

  /// Gira ([x], [y]) (con `y` hacia abajo) el rumbo [grados] hacia la izquierda: lo que está al
  /// [grados] a la derecha del norte pasa a estar arriba.
  static ({double x, double y}) _girar(double x, double y, double grados) {
    if (grados == 0) return (x: x, y: y);
    final radianes = grados * math.pi / 180;
    final c = math.cos(radianes);
    final s = math.sin(radianes);
    return (x: x * c + y * s, y: -x * s + y * c);
  }

  /// El área que se ve con [camara] en una vista de [ancho] × [alto] píxeles. Si la vista abarca
  /// más que el mundo, es el mundo entero a lo ancho; si cruza el antimeridiano, `oeste > este`
  /// (ver [AreaMapa]).
  static AreaMapa areaVisible(CamaraMapa camara, {required double ancho, required double alto}) {
    final zoom = camara.zoom;
    final mundo = tamanoMundo(zoom);
    final centro = aPixeles(camara.centro, zoom);
    final arriba = math.max(0.0, centro.y - alto / 2);
    final abajo = math.min(mundo, centro.y + alto / 2);
    final noroeste = aCoordenadas(centro.x - ancho / 2, arriba, zoom);
    final sureste = aCoordenadas(centro.x + ancho / 2, abajo, zoom);
    final sinCorte = ancho >= mundo;
    return AreaMapa(
      sur: sureste.lat,
      oeste: sinCorte ? -180 : _normalizarLongitud(noroeste.lon),
      norte: noroeste.lat,
      este: sinCorte ? 180 : _normalizarLongitud(sureste.lon),
    );
  }

  /// La cámara que deja a todos los [puntos] dentro de una vista de [ancho] × [alto], con [margen]
  /// píxeles libres en cada borde: el zoom más grande que los abarca (sin pasar de [zoomMaximo]) y
  /// el centro de su recuadro. Con un solo punto, o varios en el mismo lugar, es ese punto a
  /// [zoomMaximo].
  static CamaraMapa camaraQueAjusta(
    List<Coordenadas> puntos, {
    required double ancho,
    required double alto,
    double margen = 0,
    double zoomMaximo = 18,
  }) {
    if (puntos.isEmpty) throw ArgumentError.value(puntos, 'puntos', 'no puede estar vacía');
    final enMundo = [for (final p in puntos) aPixeles(p, 0)];
    var minX = enMundo.first.x, maxX = minX;
    var minY = enMundo.first.y, maxY = minY;
    for (final p in enMundo) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    final libreAncho = math.max(ancho - 2 * margen, 1.0);
    final libreAlto = math.max(alto - 2 * margen, 1.0);
    final anchoPuntos = maxX - minX;
    final altoPuntos = maxY - minY;
    var zoom = zoomMaximo;
    if (anchoPuntos > 0) zoom = math.min(zoom, _log2(libreAncho / anchoPuntos));
    if (altoPuntos > 0) zoom = math.min(zoom, _log2(libreAlto / altoPuntos));
    return CamaraMapa(
      centro: aCoordenadas((minX + maxX) / 2, (minY + maxY) / 2, 0),
      zoom: math.max(zoom, 0),
    );
  }

  static double _log2(double x) => math.log(x) / math.ln2;

  static double _normalizarLongitud(double lon) {
    final vuelta = ((lon + 180) % 360 + 360) % 360 - 180;
    // Un borde justo en +180 cae en -180 con la cuenta de arriba: se conserva en +180.
    return vuelta == -180 && lon > 0 ? 180 : vuelta;
  }
}
