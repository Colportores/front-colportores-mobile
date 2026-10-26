import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../data/datasources/ubicacion_alternativa_local_data_source_drift.dart';
import '../../data/repositories/ubicacion_alternativa_repository_impl.dart';
import '../../domain/entities/estado_ubicacion_alternativa.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/repositories/ubicacion_alternativa_repository.dart';
import '../../domain/usecases/ubicacion_alternativa_use_cases.dart';
import 'personas_providers.dart';

// Cableado de la ubicación alternativa de cobranza (HU-UBI-013). El vínculo sube al sync solo con ids
// (ADR-017) por el motor que cablea `encoladorSyncProvider`. El reloj es el de `personas_providers.dart`.

/// Riverpod 3 reintenta 10 veces lo que falla: la pantalla muestra el error enseguida y el
/// «Reintentar» es de quien lo toca.
Duration? _sinReintentos(int intento, Object error) => null;

final ubicacionAlternativaRepositoryProvider = Provider<UbicacionAlternativaRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return UbicacionAlternativaRepositoryImpl(
    UbicacionAlternativaLocalDataSourceDrift(db, encolador: ref.watch(encoladorSyncProvider)),
  );
});

final establecerUbicacionAlternativaUseCaseProvider =
    Provider<EstablecerUbicacionAlternativaUseCase>(
      (ref) => EstablecerUbicacionAlternativaUseCase(
        ref.watch(ubicacionAlternativaRepositoryProvider),
        ahora: ref.watch(relojPersonaProvider),
      ),
    );

final quitarUbicacionAlternativaUseCaseProvider = Provider<QuitarUbicacionAlternativaUseCase>(
  (ref) => QuitarUbicacionAlternativaUseCase(
    ref.watch(ubicacionAlternativaRepositoryProvider),
    ahora: ref.watch(relojPersonaProvider),
  ),
);

/// De quién y de dónde se pregunta: la persona y el espacio donde se le cobra.
typedef ClaveAlternativa = ({String personaId, String espacioId});

/// De quién cobra y para qué espacio se elige.
typedef ClaveCandidatasAlternativa = ({String colportorId, String espacioId});

/// Dónde se le cobra a la persona, al día cuando se elige, se quita o se da de baja la alternativa.
/// Una falla de lectura es el error del provider.
final ubicacionAlternativaProvider = StreamProvider.autoDispose
    .family<EstadoUbicacionAlternativa, ClaveAlternativa>(
      (ref, clave) => ObservarUbicacionAlternativaUseCase(
        ref.watch(ubicacionAlternativaRepositoryProvider),
      )(personaId: clave.personaId, espacioId: clave.espacioId),
      retry: _sinReintentos,
    );

/// Las ubicaciones que se pueden elegir como alternativa. Vacía = el estado vacío del selector.
final candidatasAlternativaProvider = StreamProvider.autoDispose
    .family<List<Ubicacion>, ClaveCandidatasAlternativa>(
      (ref, clave) => ObservarCandidatasAlternativaUseCase(
        ref.watch(ubicacionAlternativaRepositoryProvider),
      )(colportorId: clave.colportorId, espacioId: clave.espacioId),
      retry: _sinReintentos,
    );
