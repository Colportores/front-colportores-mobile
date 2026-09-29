import 'package:equatable/equatable.dart';

import '../../../../core/usecases/use_case.dart';
import '../entities/marcador_mapa.dart';
import '../repositories/ubicacion_repository.dart';
import '../services/agrupador_marcadores.dart';
import '../value_objects/area_mapa.dart';

/// Qué mira el mapa ahora: de quién, qué recuadro y a qué zoom.
final class ConsultaMapa extends Equatable {
  const ConsultaMapa({required this.colportorId, required this.area, required this.zoom});

  final String colportorId;
  final AreaMapa area;
  final double zoom;

  @override
  List<Object?> get props => [colportorId, area, zoom];
}

/// Lo que dibuja el mapa: los grupos (cluster o marcador individual) del recuadro visible.
final class MapaUbicaciones extends Equatable {
  const MapaUbicaciones({required this.grupos, required this.totalMarcadores});

  final List<GrupoMarcadores> grupos;

  /// Marcadores dentro del recuadro, antes de agrupar.
  final int totalMarcadores;

  bool get estaVacio => totalMarcadores == 0;

  @override
  List<Object?> get props => [grupos, totalMarcadores];
}

/// HU-UBI-003 — los marcadores del mapa, reactivos: cualquier alta, baja o edición vuelve a emitir.
///
/// Solo ubicaciones activas del colportor (las bajas no se muestran) dentro del recuadro visible,
/// agrupadas según el zoom. Cambiar el recuadro o el zoom es una consulta nueva (la vista
/// cancela la suscripción anterior). Sin `house_status` todavía: ver [MarcadorMapa].
final class ObservarMarcadoresMapaUseCase implements StreamUseCase<MapaUbicaciones, ConsultaMapa> {
  ObservarMarcadoresMapaUseCase(this._repositorio);

  final UbicacionRepository _repositorio;

  @override
  Stream<MapaUbicaciones> call(ConsultaMapa consulta) => _repositorio
      .observarMarcadoresEnArea(colportorId: consulta.colportorId, area: consulta.area)
      .map(
        (marcadores) => MapaUbicaciones(
          grupos: AgrupadorMarcadores.agrupar(marcadores, zoom: consulta.zoom),
          totalMarcadores: marcadores.length,
        ),
      );
}
