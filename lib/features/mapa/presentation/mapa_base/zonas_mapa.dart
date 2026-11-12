import 'package:colportores_mapa/colportores_mapa.dart';
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

/// El color de las zonas sobre el mapa. La regla y los números son los de lib-mapa (#673):
/// [TokensMapa.zonaSinColor], [TokensMapa.contrasteBordes] y [ContrasteMapa.bordeDeZona].
abstract final class ColoresZona {
  /// Si el coordinador no eligió color: el valor del móvil del token, el azul primario de la app.
  /// El panel usa otro gris hasta la decisión de UX de front-coordinadores-web#148
  /// ([ValorPendiente.pendiente]); cuando se decida, llega como valor único con un tag nuevo.
  static final porDefecto = Color(TokensMapa.zonaSinColor.movil);

  /// Lo peor que puede quedar detrás de un borde: el fondo liso (`ColoresMapa.fondo`, un test
  /// comprueba que sea el mismo) y el verde de los parques del estilo. El borde tiene que verse con
  /// ≥ 3:1 sobre los dos (WCAG 1.4.11). Son los de [TokensMapa.contrasteFondosDelMapa].
  static final fondoLiso = Color(TokensMapa.contrasteFondosDelMapa.first);

  /// El contraste mínimo de un borde que se tiene que ver para entender el mapa (WCAG 1.4.11).
  static const contrasteMinimo = TokensMapa.contrasteBordes;

  static final _hex = RegExp(r'^#([0-9A-Fa-f]{6})$');

  /// El color del borde de una zona con [hex] (`#RRGGBB` o `null`): el elegido por el coordinador y,
  /// si no alcanza [contrasteMinimo] sobre el mapa (un amarillo, un celeste), el mismo tono
  /// oscurecido hasta que alcance ([ContrasteMapa.bordeDeZona], la misma regla que el panel).
  static Color borde(String? hex) {
    final coincidencia = hex == null ? null : _hex.firstMatch(hex);
    final elegido = coincidencia == null
        ? porDefecto.toARGB32()
        : 0xFF000000 | int.parse(coincidencia.group(1)!, radix: 16);
    return Color(ContrasteMapa.bordeDeZona(elegido));
  }

  /// El menor contraste de [color] contra los fondos del mapa ([ContrasteMapa.sobreElMapa]).
  static double contraste(Color color) => ContrasteMapa.sobreElMapa(color.toARGB32());
}
