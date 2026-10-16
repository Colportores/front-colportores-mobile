import '../../../../core/usecases/use_case.dart';
import '../entities/paquete_tiles.dart';
import '../repositories/paquetes_tiles_repository.dart';

/// HU-UBI-003 — el paquete offline que tiene que usar el mapa para el lugar del colportor, al día
/// con cada descarga y cada eliminación. `null` si no hay ninguno que lo cubra: el mapa cae al
/// servidor online o a "sin tiles".
///
/// Enganche con #198 (PR #216): `ResolutorFuenteTiles.resolver(hayPaqueteOffline: paquete !=
/// null, ...)`, y los archivos que abre MapLibre (`pmtiles://file://` más la ruta, ver `FuenteMapa`)
/// son [PaqueteDescargado.rutas], uno por parte del paquete.
final class ObservarPaqueteOfflineUseCase
    implements StreamUseCase<PaqueteDescargado?, AmbitoTrabajo> {
  ObservarPaqueteOfflineUseCase(this._repository);

  final PaquetesTilesRepository _repository;

  @override
  Stream<PaqueteDescargado?> call(AmbitoTrabajo ambito) {
    final descargados = _repository.observarDescargados();
    return descargados.map((lista) => elegirPaqueteOffline(lista, ambito)).distinct();
  }
}
