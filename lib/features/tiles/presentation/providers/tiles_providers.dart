import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/estado_descarga.dart';
import '../../domain/repositories/paquetes_tiles_repository.dart';
import '../../domain/services/descargador_paquetes_tiles.dart';
import '../../domain/services/puertos_descarga.dart' show SondaArchivoTiles;
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

/// La prueba del archivo del mapa en línea (#299). Sin default, como el descargador: `main.dart` la
/// sobreescribe con `ComposicionTiles.sonda` y los tests con una falsa. Quien la lee sin cablear no
/// afirma nada (no hay prueba, no hay aviso).
final sondaArchivoTilesProvider = Provider<SondaArchivoTiles>((ref) {
  throw UnimplementedError('sondaArchivoTilesProvider se sobreescribe en main.dart');
});

/// Cada cambio de estado de las descargas (progreso, pausa, fin, falla), para quien tiene que
/// reaccionar a una falla. Sin el descargador cableado emite un error: quien lo lee no afirma nada.
final estadosDescargaTilesProvider = StreamProvider<EstadoDescarga>(
  (ref) => ref.watch(descargadorPaquetesTilesProvider).cambios,
);

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
