import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../data/datasources/pares_duplicados_local_data_source_drift.dart';
import '../../data/repositories/pares_duplicados_repository_impl.dart';
import '../../domain/repositories/pares_duplicados_repository.dart';
import '../../domain/usecases/duplicados_ubicacion_use_cases.dart';
import 'alta_ubicacion_providers.dart';

// Cableado de «Posibles duplicados» (HU-UBI-006, vista 10). Comparte con el alta el repositorio de
// ubicaciones, el reloj y el puerto del trabajo «marcar como duplicado».

/// Las decisiones sobre los pares (`ubicacion_par_decidido`). Sin DB abierta no hay dónde leerlas:
/// lanza, y quien lo lee lo traduce a una falla.
final paresDuplicadosRepositoryProvider = Provider<ParesDuplicadosRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return ParesDuplicadosRepositoryImpl(ParesDuplicadosLocalDataSourceDrift(db));
});

/// Los pares de la pantalla, reactivos: un par unido, decidido o corregido sale solo.
final observarParesDuplicadosUseCaseProvider = Provider<ObservarParesDuplicadosUseCase>(
  (ref) => ObservarParesDuplicadosUseCase(
    ref.watch(ubicacionRepositoryProvider),
    ref.watch(paresDuplicadosRepositoryProvider),
    ahora: ref.watch(relojAltaUbicacionProvider),
  ),
);

/// «Son distintos» e «Ignorar».
final decidirParDuplicadoUseCaseProvider = Provider<DecidirParDuplicadoUseCase>(
  (ref) => DecidirParDuplicadoUseCase(
    ref.watch(paresDuplicadosRepositoryProvider),
    ahora: ref.watch(relojAltaUbicacionProvider),
  ),
);

/// La unión local y definitiva de un par, que corre pasados los 8 s de «Deshacer».
final unirDuplicadosUseCaseProvider = Provider<UnirDuplicadosUseCase>(
  (ref) => UnirDuplicadosUseCase(
    ref.watch(ubicacionRepositoryProvider),
    ahora: ref.watch(relojAltaUbicacionProvider),
  ),
);

/// Cuánto espera «Conservar A y unir» antes de hacerse (canvas 10·03 y HU-UBI-006: 8 s). Un test lo
/// acorta.
final plazoDeshacerUnionProvider = Provider<Duration>((ref) => const Duration(seconds: 8));

/// Los pares que quedan para revisar del colportor [colportorId]. Sin DB abierta no hay pares: la
/// lista sale vacía, igual que las demás lecturas del mapa.
final paresParaRevisarProvider = StreamProvider.autoDispose.family<List<ParaRevisar>, String>((
  ref,
  colportorId,
) {
  if (ref.watch(dbLocalProvider) == null) return Stream.value(const []);
  return ref.watch(observarParesDuplicadosUseCaseProvider)(colportorId);
});

/// Cuántos pares hay para revisar: el aviso «N posibles duplicados · Revisar» de la Lista y el
/// contador del badge del menú (HU-NOT). **0 mientras se lee o si nunca se pudo leer**: un aviso que
/// no se puede confirmar no se muestra. Si una lectura falla después de una buena, queda la última.
final cantidadParesParaRevisarProvider = Provider.autoDispose.family<int, String>(
  (ref, colportorId) => ref.watch(paresParaRevisarProvider(colportorId)).value?.length ?? 0,
);
