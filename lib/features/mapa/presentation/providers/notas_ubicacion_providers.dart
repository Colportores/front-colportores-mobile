import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../data/datasources/nota_ubicacion_local_data_source_drift.dart';
import '../../data/repositories/nota_ubicacion_repository_impl.dart';
import '../../domain/entities/nota_ubicacion.dart';
import '../../domain/repositories/nota_ubicacion_repository.dart';
import '../../domain/usecases/notas_ubicacion_use_cases.dart';
import 'personas_providers.dart';

// Cableado de las notas de un lugar (vista 39, C·05). Presentation conoce domain; data se inyecta acá.
// Todo es local: las notas no se sincronizan ni salen del teléfono. El generador de ids y el reloj son
// los de las personas (`generadorIdPersonaProvider`, `relojPersonaProvider`).

/// Riverpod 3 reintenta 10 veces lo que falla: la pestaña muestra el error enseguida y el
/// «Reintentar» es de quien lo toca.
Duration? _sinReintentos(int intento, Object error) => null;

final notaUbicacionRepositoryProvider = Provider<NotaUbicacionRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return NotaUbicacionRepositoryImpl(NotaUbicacionLocalDataSourceDrift(db));
});

final agregarNotaUbicacionUseCaseProvider = Provider<AgregarNotaUbicacionUseCase>(
  (ref) => AgregarNotaUbicacionUseCase(
    ref.watch(notaUbicacionRepositoryProvider),
    ahora: ref.watch(relojPersonaProvider),
  ),
);

final editarNotaUbicacionUseCaseProvider = Provider<EditarNotaUbicacionUseCase>(
  (ref) => EditarNotaUbicacionUseCase(
    ref.watch(notaUbicacionRepositoryProvider),
    ahora: ref.watch(relojPersonaProvider),
  ),
);

final borrarNotaUbicacionUseCaseProvider = Provider<BorrarNotaUbicacionUseCase>(
  (ref) => BorrarNotaUbicacionUseCase(
    ref.watch(notaUbicacionRepositoryProvider),
    ahora: ref.watch(relojPersonaProvider),
  ),
);

final restaurarNotaUbicacionUseCaseProvider = Provider<RestaurarNotaUbicacionUseCase>(
  (ref) => RestaurarNotaUbicacionUseCase(
    ref.watch(notaUbicacionRepositoryProvider),
    ahora: ref.watch(relojPersonaProvider),
  ),
);

/// Todas las notas de [ubicacionId], activas y borradas, de la más nueva a la más vieja, al día cuando
/// se agrega, edita, borra o restaura una. Una falla de lectura es el error del provider.
final notasDeUbicacionProvider = StreamProvider.autoDispose.family<List<NotaUbicacion>, String>(
  (ref, ubicacionId) => ref.watch(notaUbicacionRepositoryProvider).observar(ubicacionId),
  retry: _sinReintentos,
);
