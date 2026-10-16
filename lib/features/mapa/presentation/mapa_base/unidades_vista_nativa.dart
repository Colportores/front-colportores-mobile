import 'package:flutter/foundation.dart' show TargetPlatform;

/// Cuántas unidades de la vista nativa del mapa tiene un dp, según para qué se use.
///
/// Los toques y las consultas no son lo mismo que las imágenes: Android da los toques en píxeles
/// nativos y iOS en puntos, pero los dos plugins muestran una imagen registrada en el estilo
/// (`addImage`) con la densidad de la pantalla (iOS la arma con `UIScreen.scale`), así que la
/// etiqueta se pinta a `densidad` píxeles por dp en ambas. Con 1 en iOS se vería a 1/2 o 1/3.
abstract final class UnidadesVistaNativa {
  /// Del dp a las unidades en que la vista da y consulta un toque: la [densidad] de píxeles en
  /// Android y 1 (puntos) en iOS.
  static double paraToques({required TargetPlatform plataforma, required double densidad}) =>
      plataforma == TargetPlatform.android ? densidad : 1;

  /// Píxeles por dp con que se pinta una imagen que se registra en el estilo: la [densidad] de la
  /// pantalla, en cualquier plataforma.
  static double paraImagenes({required double densidad}) => densidad;
}
