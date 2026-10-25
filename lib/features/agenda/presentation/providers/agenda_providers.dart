import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../mapa/presentation/providers/house_status_providers.dart';
import '../../data/datasources/agenda_local_data_source_drift.dart';
import '../../data/repositories/agenda_repository_impl.dart';
import '../../domain/repositories/agenda_repository.dart';
import '../../domain/usecases/registrar_resultado_visita_use_case.dart';

// Cableado de las agendas y las visitas (BACK-HU-VIS-001). Presentation conoce domain; data se
// inyecta acá. Las pantallas (vista 23) y los casos de uso de HU-VIS-001 y HU-VIS-005 se apoyan en
// [agendaRepositoryProvider].

/// Guarda agendas y visitas en la DB cifrada, las encola para el sync y recalcula el color de la
/// casa en la misma transacción. Sin DB abierta no hay dónde guardar: lanza, y quien lo lee lo
/// traduce a un error de la pantalla.
final agendaRepositoryProvider = Provider<AgendaRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return AgendaRepositoryImpl(
    AgendaLocalDataSourceDrift(
      db,
      encolador: ref.watch(encoladorSyncProvider),
      estadoDeLasCasas: ref.watch(houseStatusUpdaterProvider),
    ),
  );
});

/// Generador de UUID v7 del registro de un resultado; un test lo reemplaza para fijar los ids.
final generadorIdVisitaProvider = Provider<String Function()>((ref) => const Uuid().v7);

/// Reloj del registro de un resultado; un test lo reemplaza.
final relojVisitaProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// HU-VIS-005: registrar el resultado de una visita. La pantalla de resultados (#411) lo usa.
final registrarResultadoVisitaUseCaseProvider = Provider<RegistrarResultadoVisitaUseCase>(
  (ref) => RegistrarResultadoVisitaUseCase(
    ref.watch(agendaRepositoryProvider),
    generarId: ref.watch(generadorIdVisitaProvider),
    ahora: ref.watch(relojVisitaProvider),
  ),
);
