import 'package:equatable/equatable.dart';

import 'paquete_tiles.dart';

/// Dónde trabaja el colportor, con los nombres que ve en «Mapas offline» (HU-SYNC-010): su zona
/// asignada y su ciudad. [ambito] trae los ids con los que se elige el paquete del catálogo; el
/// nombre de la zona sale de la réplica local (los paquetes de zona no lo traen: el catálogo es
/// público).
final class LugarDeTrabajo extends Equatable {
  const LugarDeTrabajo({required this.ambito, this.zonaNombre, this.ciudadNombre});

  final AmbitoTrabajo ambito;

  /// `null` si no tiene zona asignada (en ese caso `ambito.zonaId` también es `null`).
  final String? zonaNombre;

  /// `null` si no se conoce el nombre de la ciudad.
  final String? ciudadNombre;

  @override
  List<Object?> get props => [ambito, zonaNombre, ciudadNombre];
}
