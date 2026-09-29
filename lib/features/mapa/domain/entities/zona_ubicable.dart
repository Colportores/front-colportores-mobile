import 'package:equatable/equatable.dart';

import '../value_objects/geometria_zona.dart';

/// Lo que hace falta de una zona para ubicar un punto en ella: su forma, y la campaña y la ciudad
/// de su `campania_ciudad` (backend-supabase 0008: `zona` cuelga de `campania_ciudad`).
///
/// `ZonaRepository` entrega solo zonas **vivas** (la zona y su `campania_ciudad` sin baja): una
/// zona dada de baja no cubre nada.
final class ZonaUbicable extends Equatable {
  const ZonaUbicable({
    required this.zonaId,
    required this.campaniaId,
    required this.ciudadId,
    required this.geometria,
  });

  final String zonaId;
  final String campaniaId;
  final String ciudadId;
  final GeometriaZona geometria;

  @override
  List<Object?> get props => [zonaId, campaniaId, ciudadId, geometria];
}
