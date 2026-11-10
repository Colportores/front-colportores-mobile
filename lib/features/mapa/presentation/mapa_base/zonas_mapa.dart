import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

import '../../domain/entities/zona_del_mapa.dart';
import '../../domain/services/punto_rotulo_de_zona.dart';
import '../../domain/value_objects/coordenadas.dart';
import '../formato_zonas_mapa.dart';

/// Una zona lista para dibujar sobre `MapaBase` (#511): el estilo de zona del panel (vista 24,
/// relleno translúcido y borde del color de la zona) con el retoque del teléfono: la zona propia
/// resaltada y las demás tenues.
final class ZonaMapa extends Equatable {
  const ZonaMapa({
    required this.id,
    required this.rotulo,
    required this.poligonos,
    required this.color,
    required this.propia,
    this.puntoRotulo,
  });

  /// La zona del dominio ya resuelta para dibujar: el color con contraste suficiente y el punto del
  /// nombre adentro de la zona.
  factory ZonaMapa.desde(ZonaDelMapa zona) => ZonaMapa(
    id: zona.id,
    rotulo: zona.propia ? TextosMapaZonas.rotuloPropia(zona.nombre) : zona.nombre,
    poligonos: zona.geometria.poligonos,
    color: ColoresZona.borde(zona.color),
    propia: zona.propia,
    puntoRotulo: PuntoRotuloDeZona.de(zona.geometria),
  );

  final String id;

  /// El nombre que va escrito sobre la zona («Tu zona · X» en la propia).
  final String rotulo;

  /// Cada polígono es su anillo exterior seguido de sus huecos, cerrados, en `[lat, lon]`.
  final List<List<List<Coordenadas>>> poligonos;

  /// El color del borde, ya con contraste de al menos 3:1 sobre el mapa ([ColoresZona.borde]).
  final Color color;

  final bool propia;

  /// Dónde va [rotulo]: adentro de la zona; `null` si no se encontró (la zona se dibuja igual).
  final Coordenadas? puntoRotulo;

  @override
  List<Object?> get props => [id, rotulo, poligonos, color, propia, puntoRotulo];
}

/// El color de las zonas sobre el mapa.
abstract final class ColoresZona {
  /// Si el coordinador no eligió color: el azul primario de la app.
  static const porDefecto = Color(0xFF13407A);

  /// Lo peor que puede quedar detrás de un borde: el fondo liso (`ColoresMapa.fondo`, un test
  /// comprueba que sea el mismo) y el verde de los parques del estilo (`tiles/paleta.json`). El
  /// borde tiene que verse con ≥ 3:1 sobre los dos (WCAG 1.4.11).
  static const fondoLiso = Color(0xFFF6F5F0);
  static const _fondos = [fondoLiso, Color(0xFFDDE8D3)];

  /// El contraste mínimo de un borde que se tiene que ver para entender el mapa (WCAG 1.4.11).
  static const contrasteMinimo = 3.0;

  static final _hex = RegExp(r'^#([0-9A-Fa-f]{6})$');

  /// El color del borde de una zona con [hex] (`#RRGGBB` o `null`): el elegido por el coordinador y,
  /// si no alcanza [contrasteMinimo] sobre el mapa (un amarillo, un celeste), el mismo tono
  /// oscurecido hasta que alcance.
  static Color borde(String? hex) {
    final coincidencia = hex == null ? null : _hex.firstMatch(hex);
    var color = coincidencia == null
        ? porDefecto
        : Color(0xFF000000 | int.parse(coincidencia.group(1)!, radix: 16));
    for (var i = 0; i < 40 && contraste(color) < contrasteMinimo; i++) {
      color = _aOchoBits(Color.lerp(color, const Color(0xFF000000), .08)!);
    }
    return color;
  }

  /// El color con cada canal en un entero de 8 bits: lo que el estilo del mapa escribe en hex y lo
  /// que se ve, así el contraste que se mide es el del color que se dibuja.
  static Color _aOchoBits(Color color) => Color.fromARGB(
    255,
    (color.r * 255).round(),
    (color.g * 255).round(),
    (color.b * 255).round(),
  );

  /// El menor contraste de [color] contra los fondos del mapa.
  static double contraste(Color color) {
    final claro = color.computeLuminance();
    var peor = double.infinity;
    for (final fondo in _fondos) {
      final otro = fondo.computeLuminance();
      final mayor = claro > otro ? claro : otro;
      final menor = claro > otro ? otro : claro;
      final razon = (mayor + .05) / (menor + .05);
      if (razon < peor) peor = razon;
    }
    return peor;
  }
}
