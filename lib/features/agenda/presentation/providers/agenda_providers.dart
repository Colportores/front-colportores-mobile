import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../mapa/presentation/providers/house_status_providers.dart';
import '../../data/datasources/agenda_local_data_source_drift.dart';
import '../../data/repositories/agenda_repository_impl.dart';
import '../../domain/repositories/agenda_repository.dart';

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
