import 'package:equatable/equatable.dart';

import 'coordenadas.dart';

/// La forma de una zona (`zona.poligono_geojson`): un `Polygon` o un `MultiPolygon` de GeoJSON,
/// con las coordenadas en `[lon, lat]`.
///
/// Es lo que dibujan la app y el panel y con lo que se ubica cada dirección (backend-supabase
/// 0008). [cubre] es el `ST_Covers` del servidor (0010): cálculo plano sobre lon/lat, **con el
/// borde incluido**, así que un punto justo en la calle que separa dos zonas lo cubren las dos (el
/// desempate lo hace `ZonaPorPosicion`).
///
/// Las cuentas son exactas: la orientación de un punto respecto de un lado se calcula en `double` y,
/// solo cuando el resultado queda dentro del error de redondeo, con enteros exactos. Si no, un
/// punto sobre un lado diagonal podía quedar adentro o afuera según el redondeo, y la app mostraría
/// otra zona que el servidor.
final class GeometriaZona extends Equatable {
  const GeometriaZona._(this.poligonos);

  /// Cada polígono es su anillo exterior seguido de sus huecos; cada anillo, sus puntos en orden
  /// (cerrado o no: el último punto se une con el primero).
  final List<List<List<Coordenadas>>> poligonos;

  /// La geometría de [geojson] (el objeto ya decodificado), o `null` si no es un `Polygon` ni un
  /// `MultiPolygon` bien formado: anillos de al menos 3 puntos, cada punto `[lon, lat]` numérico.
  /// El servidor valida la forma al guardarla (0008), así que `null` sería un dato roto.
  static GeometriaZona? desdeGeojson(Object? geojson) {
    if (geojson is! Map<Object?, Object?>) return null;
    final coordenadas = geojson['coordinates'];
    final List<Object?> crudos;
    switch (geojson['type']) {
      case 'Polygon':
        crudos = [coordenadas];
      case 'MultiPolygon' when coordenadas is List<Object?>:
        crudos = coordenadas;
      default:
        return null;
    }
    final poligonos = <List<List<Coordenadas>>>[];
    for (final crudo in crudos) {
      final poligono = _poligono(crudo);
      if (poligono == null) return null;
      poligonos.add(poligono);
    }
    return poligonos.isEmpty ? null : GeometriaZona._(poligonos);
  }

  /// `true` si [punto] está adentro de algún polígono o sobre su borde (el exterior o el de un
  /// hueco). Un punto dentro de un hueco queda afuera.
  bool cubre(Coordenadas punto) => poligonos.any((anillos) => _cubre(anillos, punto));

  static bool _cubre(List<List<Coordenadas>> anillos, Coordenadas punto) {
    if (anillos.any((anillo) => _enBorde(anillo, punto))) return true;
    if (!_adentro(anillos.first, punto)) return false;
    return !anillos.skip(1).any((hueco) => _adentro(hueco, punto));
  }

  static List<List<Coordenadas>>? _poligono(Object? crudo) {
    if (crudo is! List<Object?> || crudo.isEmpty) return null;
    final anillos = <List<Coordenadas>>[];
    for (final anillo in crudo) {
      final puntos = _anillo(anillo);
      if (puntos == null) return null;
      anillos.add(puntos);
    }
    return anillos;
  }

  static List<Coordenadas>? _anillo(Object? crudo) {
    if (crudo is! List<Object?> || crudo.length < 3) return null;
    final puntos = <Coordenadas>[];
    for (final punto in crudo) {
      if (punto is! List<Object?> || punto.length < 2) return null;
      final [lon, lat, ...] = punto;
      if (lon is! num || lat is! num) return null;
      puntos.add(Coordenadas(lat: lat.toDouble(), lon: lon.toDouble()));
    }
    return puntos;
  }

  /// Los lados del anillo: de cada punto al siguiente, y del último al primero.
  static Iterable<(Coordenadas, Coordenadas)> _lados(List<Coordenadas> anillo) sync* {
    for (var i = 0; i < anillo.length; i++) {
      yield (anillo[i], anillo[(i + 1) % anillo.length]);
    }
  }

  static bool _enBorde(List<Coordenadas> anillo, Coordenadas p) {
    for (final (a, b) in _lados(anillo)) {
      if (_orientacion(a, b, p) == 0 &&
          p.lon >= _min(a.lon, b.lon) &&
          p.lon <= _max(a.lon, b.lon) &&
          p.lat >= _min(a.lat, b.lat) &&
          p.lat <= _max(a.lat, b.lat)) {
        return true;
      }
    }
    return false;
  }

  /// Número de vueltas (Sunday): distinto de cero si [p] está adentro. Se llama solo con [p] fuera
  /// del borde, así que un punto justo sobre un lado nunca llega acá.
  static bool _adentro(List<Coordenadas> anillo, Coordenadas p) {
    var vueltas = 0;
    for (final (a, b) in _lados(anillo)) {
      if (a.lat <= p.lat) {
        if (b.lat > p.lat && _orientacion(a, b, p) > 0) vueltas++;
      } else if (b.lat <= p.lat && _orientacion(a, b, p) < 0) {
        vueltas--;
      }
    }
    return vueltas != 0;
  }

  static double _min(double x, double y) => x < y ? x : y;
  static double _max(double x, double y) => x > y ? x : y;

  /// 2⁻⁵³: la mitad de la distancia entre 1 y el `double` siguiente.
  static const double _epsilon = 1.1102230246251565e-16;

  /// Cota del error de redondeo de la orientación en `double` (Shewchuk, «Adaptive Precision
  /// Floating-Point Arithmetic», `ccwerrboundA`).
  static const double _cotaError = (3 + 16 * _epsilon) * _epsilon;

  /// Signo de la orientación de [c] respecto del lado [a]→[b] (x = lon, y = lat): 1 a la izquierda,
  /// -1 a la derecha, 0 sobre la recta.
  static int _orientacion(Coordenadas a, Coordenadas b, Coordenadas c) {
    final izquierda = (a.lon - c.lon) * (b.lat - c.lat);
    final derecha = (a.lat - c.lat) * (b.lon - c.lon);
    final determinante = izquierda - derecha;
    final cota = _cotaError * (izquierda.abs() + derecha.abs());
    if (determinante > cota) return 1;
    if (-determinante > cota) return -1;
    return _orientacionExacta(a, b, c);
  }

  /// La misma cuenta con enteros: todo `double` finito es un entero dividido por una potencia de 2,
  /// así que con el mismo divisor para las seis coordenadas el signo sale exacto.
  static int _orientacionExacta(Coordenadas a, Coordenadas b, Coordenadas c) {
    final racionales = [
      for (final v in [a.lon, a.lat, b.lon, b.lat, c.lon, c.lat]) _racional(v),
    ];
    final exponente = racionales.map((r) => r.exponente).reduce((x, y) => x > y ? x : y);
    final [ax, ay, bx, by, cx, cy] = [
      for (final r in racionales) r.numerador << (exponente - r.exponente),
    ];
    return ((ax - cx) * (by - cy) - (ay - cy) * (bx - cx)).sign;
  }

  /// [valor] = `numerador / 2^exponente`, exacto: multiplicar por 2 no redondea.
  static ({BigInt numerador, int exponente}) _racional(double valor) {
    var escalado = valor;
    var exponente = 0;
    while (escalado != escalado.truncateToDouble()) {
      escalado *= 2;
      exponente++;
    }
    return (numerador: BigInt.from(escalado), exponente: exponente);
  }

  @override
  List<Object?> get props => [poligonos];
}
