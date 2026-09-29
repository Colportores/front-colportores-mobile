import 'package:equatable/equatable.dart';

import '../value_objects/coordenadas.dart';
import 'ubicacion.dart';

/// Lo que el mapa necesita de una ubicación activa para dibujar su marcador y su preview
/// (HU-UBI-003): tipo, dirección y número de espacios.
///
/// **No tiene estado (`house_status`)**: no hay tabla local de la que leerlo, así que el color
/// del marcador queda pendiente de esa decisión (ver el comentario del issue #198, que remite al
/// de #195). Tampoco hay color ni paleta acá: eso es de la vista.
final class MarcadorMapa extends Equatable {
  const MarcadorMapa({
    required this.ubicacionId,
    required this.tipo,
    required this.lat,
    required this.lon,
    this.calle,
    this.numero,
    this.cantidadEspacios = 0,
  });

  final String ubicacionId;
  final TipoUbicacion tipo;
  final double lat;
  final double lon;
  final String? calle;
  final String? numero;

  /// Espacios (deptos) no dados de baja de la ubicación.
  final int cantidadEspacios;

  Coordenadas get coordenadas => Coordenadas(lat: lat, lon: lon);

  @override
  List<Object?> get props => [ubicacionId, tipo, lat, lon, calle, numero, cantidadEspacios];
}

/// Uno o varios marcadores que se dibujan como uno solo a un zoom dado (cluster).
final class GrupoMarcadores extends Equatable {
  const GrupoMarcadores({required this.marcadores, required this.centro});

  /// Al menos uno, ordenados por `ubicacionId`.
  final List<MarcadorMapa> marcadores;

  /// Promedio de las coordenadas de los marcadores (el punto del cluster).
  final Coordenadas centro;

  int get cantidad => marcadores.length;

  /// Un solo marcador: se dibuja tal cual, no como cluster con contador.
  bool get esIndividual => marcadores.length == 1;

  @override
  List<Object?> get props => [marcadores, centro];
}
