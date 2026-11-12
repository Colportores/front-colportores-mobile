import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/error/failure.dart';
import '../../data/datasources/nota_persona_local_data_source_drift.dart';
import '../../data/repositories/nota_persona_repository_impl.dart';
import '../../domain/entities/contexto_notas_persona.dart';
import '../../domain/entities/nota_persona.dart';
import '../../domain/repositories/nota_persona_repository.dart';
import '../../domain/usecases/notas_persona_use_cases.dart';
import 'personas_providers.dart';

// Cableado de las notas de una persona (HU-UBI-012, vista 32E). Presentation conoce domain; data se
// inyecta acá. Todo es local: las notas no se sincronizan ni salen del teléfono. El generador de ids y
// el reloj son los de las personas (`generadorIdPersonaProvider`, `relojPersonaProvider`).

/// Riverpod 3 reintenta 10 veces lo que falla: la pantalla muestra el error enseguida y el
/// «Reintentar» es de quien lo toca.
Duration? _sinReintentos(int intento, Object error) => null;

final notaPersonaRepositoryProvider = Provider<NotaPersonaRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return NotaPersonaRepositoryImpl(NotaPersonaLocalDataSourceDrift(db));
});

final agregarNotaPersonaUseCaseProvider = Provider<AgregarNotaPersonaUseCase>(
  (ref) => AgregarNotaPersonaUseCase(
    ref.watch(notaPersonaRepositoryProvider),
    ahora: ref.watch(relojPersonaProvider),
  ),
);

final editarNotaPersonaUseCaseProvider = Provider<EditarNotaPersonaUseCase>(
  (ref) => EditarNotaPersonaUseCase(
    ref.watch(notaPersonaRepositoryProvider),
    ahora: ref.watch(relojPersonaProvider),
  ),
);

final borrarNotaPersonaUseCaseProvider = Provider<BorrarNotaPersonaUseCase>(
  (ref) => BorrarNotaPersonaUseCase(
    ref.watch(notaPersonaRepositoryProvider),
    ahora: ref.watch(relojPersonaProvider),
  ),
);

final restaurarNotaPersonaUseCaseProvider = Provider<RestaurarNotaPersonaUseCase>(
  (ref) => RestaurarNotaPersonaUseCase(
    ref.watch(notaPersonaRepositoryProvider),
    ahora: ref.watch(relojPersonaProvider),
  ),
);

/// Todas las notas de [personaId], activas y borradas, de la más nueva a la más vieja, al día cuando
/// se agrega, edita, borra o restaura una. Una falla de lectura es el error del provider.
final notasDePersonaProvider = StreamProvider.autoDispose.family<List<NotaPersona>, String>(
  (ref, personaId) => ref.watch(notaPersonaRepositoryProvider).observar(personaId),
  retry: _sinReintentos,
);

/// El nombre de la persona y si sus notas son de solo lectura, o `null` si ya no está en el teléfono.
final contextoNotasPersonaProvider = FutureProvider.autoDispose
    .family<ContextoNotasPersona?, String>((ref, personaId) async {
      final lectura = await ref.watch(notaPersonaRepositoryProvider).leerContexto(personaId);
      return lectura.fold((Failure falla) => throw falla, (contexto) => contexto);
    }, retry: _sinReintentos);
