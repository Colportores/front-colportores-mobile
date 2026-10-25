import '../value_objects/camara_mapa.dart';
import '../value_objects/coordenadas.dart';
import 'proyeccion_mercator.dart';

/// Cuándo el mapa deja de mostrar puntos de color y pasa a mostrar cuadrados con el número de cada
/// casa (vista 39, M·02).
///
/// La regla es la decisión de Cristian del 23/10 («Números casas»: «Cuadrados solo si entran»): no
/// hay un zoom fijo. El mapa sigue con los puntos de color y los grupos de HU-UBI-003 hasta que,
/// acercando con los dedos, **entran todos** los cuadrados de lo que se ve sin taparse entre sí. Nunca
/// se tapa una casa con otra, y no hay botón ni aviso que pida acercar.
///
/// Es una función pura de la cámara, el tamaño de la vista y las coordenadas de las casas.
abstract final class CuadradosDelMapa {
  /// El lado de un cuadrado (M·02: «un cuadrado de 40 px»), en dp.
  static const ladoDp = 40.0;

  /// Lo que tiene que quedar libre entre dos cuadrados vecinos para que se lean como dos: sin esto,
  /// dos cuadrados pegados parecen uno solo.
  static const separacionDp = 2.0;

  /// ¿Entran sin taparse todos los cuadrados de las [casas] que se ven con [camara] en una vista de
  /// [ancho] × [alto] dp?
  ///
  /// Cuenta cada casa cuyo cuadrado se ve aunque sea en parte (el borde de la vista corta a las de
  /// la orilla, y una que se ve a medias también tapa a su vecina). [reservaInferior] es lo que la
  /// hoja de abajo deja sin ver. Dos casas en el mismo punto no entran nunca. Sin casas a la vista,
  /// `false`: no hay nada que dibujar.
  static bool entranTodos({
    required Iterable<Coordenadas> casas,
    required CamaraMapa camara,
    required double ancho,
    required double alto,
    double reservaInferior = 0,
  }) {
    if (!ancho.isFinite || !alto.isFinite || ancho <= 0 || alto <= 0) return false;
    final visibleAlto = alto - reservaInferior;
    if (visibleAlto <= 0) return false;

    final centro = ProyeccionMercator.aPixeles(camara.centro, camara.zoom);
    const mitad = ladoDp / 2;
    final vistas = <({double x, double y})>[];
    for (final casa in casas) {
      final mundo = ProyeccionMercator.aPixeles(casa, camara.zoom);
      final x = mundo.x - centro.x + ancho / 2;
      final y = mundo.y - centro.y + alto / 2;
      if (x < -mitad || x > ancho + mitad || y < -mitad || y > visibleAlto + mitad) continue;
      vistas.add((x: x, y: y));
    }
    if (vistas.isEmpty) return false;

    // Más casas que cuadrados que caben en la vista: no hay forma de que entren, y no hace falta
    // mirarlas de a pares.
    const paso = ladoDp + separacionDp;
    final cabenAncho = ((ancho + ladoDp) / paso).ceil();
    final cabenAlto = ((visibleAlto + ladoDp) / paso).ceil();
    if (vistas.length > cabenAncho * cabenAlto) return false;

    // Una grilla de celdas de un cuadrado: solo se comparan las casas de celdas vecinas.
    final celdas = <int, List<int>>{};
    int clave(int cx, int cy) => cx * 100003 + cy;
    for (var i = 0; i < vistas.length; i++) {
      final v = vistas[i];
      (celdas[clave((v.x / paso).floor(), (v.y / paso).floor())] ??= []).add(i);
    }
    for (var i = 0; i < vistas.length; i++) {
      final v = vistas[i];
      final cx = (v.x / paso).floor();
      final cy = (v.y / paso).floor();
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          for (final j in celdas[clave(cx + dx, cy + dy)] ?? const <int>[]) {
            if (j == i) continue;
            final otra = vistas[j];
            if ((otra.x - v.x).abs() < paso && (otra.y - v.y).abs() < paso) return false;
          }
        }
      }
    }
    return true;
  }
}
