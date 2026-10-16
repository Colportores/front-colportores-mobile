import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/usecases/modificar_ubicacion_use_case.dart';
import 'alta_ubicacion_providers.dart';

// Cableado de la edición de una ubicación (HU-UBI-004, vista 07). Comparte con el alta el repositorio,
// el ubicador de zona, el reloj y los puertos del mapa (GPS, geocodificador, ciudades de la campaña).

/// El caso de uso de HU-UBI-004 (#201): valida, pide las confirmaciones, controla la edición
/// concurrente y escribe en el teléfono con el sync encolado.
final modificarUbicacionUseCaseProvider = Provider<ModificarUbicacionUseCase>(
  (ref) => ModificarUbicacionUseCase(
    ref.watch(ubicacionRepositoryProvider),
    ubicador: ref.watch(ubicadorZonaProvider),
    ahora: ref.watch(relojAltaUbicacionProvider),
  ),
);
