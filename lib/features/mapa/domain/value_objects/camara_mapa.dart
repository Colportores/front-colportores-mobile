import 'package:equatable/equatable.dart';

import 'coordenadas.dart';

/// Hacia dónde mira el mapa: el punto del centro y el zoom (escala de MapLibre: teselas de 512 px,
/// zoom 0 = el mundo entero en 512 px). Sin rotación ni inclinación: la app no las usa.
final class CamaraMapa extends Equatable {
  const CamaraMapa({required this.centro, required this.zoom});

  final Coordenadas centro;
  final double zoom;

  CamaraMapa conCentro(Coordenadas nuevo) => CamaraMapa(centro: nuevo, zoom: zoom);

  CamaraMapa conZoom(double nuevo) => CamaraMapa(centro: centro, zoom: nuevo);

  @override
  List<Object?> get props => [centro, zoom];
}
