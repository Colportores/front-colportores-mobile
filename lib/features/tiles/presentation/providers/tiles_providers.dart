import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/paquetes_tiles_repository.dart';
import '../../domain/services/descargador_paquetes_tiles.dart';
import '../../domain/usecases/descarga_paquete_tiles_use_cases.dart';
import '../../domain/usecases/listar_cobertura_tiles_use_case.dart';
import '../../domain/usecases/observar_paquete_offline_use_case.dart';
import '../../domain/usecases/sugerir_paquete_tiles_use_case.dart';

// Cableado de los paquetes de mapas (HU-SYNC-010, #189).
//
// [paquetesTilesRepositoryProvider] y [descargadorPaquetesTilesProvider] no tienen implementación
// por defecto —igual que los data sources de auth y el almacén seguro—: `main.dart` los
// sobreescribe con los adaptadores reales (`ComposicionTiles`) y los tests con fakes. Así ningún
// test toca la red ni el disco del dispositivo sin decirlo.

final paquetesTilesRepositoryProvider = Provider<PaquetesTilesRepository>((ref) {
  throw UnimplementedError('paquetesTilesRepositoryProvider se sobreescribe en main.dart');
});

/// Una sola instancia por app: guarda en memoria el estado de las descargas y escucha la
/// conectividad.
final descargadorPaquetesTilesProvider = Provider<DescargadorPaquetesTiles>((ref) {
  throw UnimplementedError('descargadorPaquetesTilesProvider se sobreescribe en main.dart');
});

final listarCoberturaTilesUseCaseProvider = Provider<ListarCoberturaTilesUseCase>(
  (ref) => ListarCoberturaTilesUseCase(ref.watch(paquetesTilesRepositoryProvider)),
);

final sugerirPaqueteTilesUseCaseProvider = Provider<SugerirPaqueteTilesUseCase>(
  (ref) => SugerirPaqueteTilesUseCase(ref.watch(paquetesTilesRepositoryProvider)),
);

final observarPaqueteOfflineUseCaseProvider = Provider<ObservarPaqueteOfflineUseCase>(
  (ref) => ObservarPaqueteOfflineUseCase(ref.watch(paquetesTilesRepositoryProvider)),
);

final descargarPaqueteTilesUseCaseProvider = Provider<DescargarPaqueteTilesUseCase>(
  (ref) => DescargarPaqueteTilesUseCase(ref.watch(descargadorPaquetesTilesProvider)),
);

final pausarDescargaTilesUseCaseProvider = Provider<PausarDescargaTilesUseCase>(
  (ref) => PausarDescargaTilesUseCase(ref.watch(descargadorPaquetesTilesProvider)),
);

final eliminarPaqueteTilesUseCaseProvider = Provider<EliminarPaqueteTilesUseCase>(
  (ref) => EliminarPaqueteTilesUseCase(ref.watch(descargadorPaquetesTilesProvider)),
);
