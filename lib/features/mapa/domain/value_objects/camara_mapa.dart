import 'package:equatable/equatable.dart';

import 'coordenadas.dart';

/// Hacia dónde mira el mapa: el punto del centro, el zoom (escala de MapLibre: teselas de 512 px,
/// zoom 0 = el mundo entero en 512 px) y el rumbo. Sin inclinación: la app no la usa. El rumbo solo
/// lo mueve el seguimiento «Seguir y girar» (#670): ningún gesto del colportor rota el mapa.
final class CamaraMapa extends Equatable {
  const CamaraMapa({required this.centro, required this.zoom, this.rumbo = 0});

  final Coordenadas centro;
  final double zoom;

  /// Hacia dónde mira el mapa, en grados desde el norte en el sentido de las agujas del reloj: con 0
  /// el norte queda arriba y con 90 queda arriba el este.
  final double rumbo;

  CamaraMapa conCentro(Coordenadas nuevo) => CamaraMapa(centro: nuevo, zoom: zoom, rumbo: rumbo);

  CamaraMapa conZoom(double nuevo) => CamaraMapa(centro: centro, zoom: nuevo, rumbo: rumbo);

  CamaraMapa conRumbo(double nuevo) => CamaraMapa(centro: centro, zoom: zoom, rumbo: nuevo);

  @override
  List<Object?> get props => [centro, zoom, rumbo];
}
