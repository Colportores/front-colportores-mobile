import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../data/services/house_status_updater_drift.dart';
import '../../domain/services/house_status_updater.dart';

// Cableado de la cache `house_status` (ADR-003, R-UB08). Presentation conoce domain; data se inyecta
// acá. El servicio escribe en la DB cifrada y encola por el motor que ya cablea
// `encoladorSyncProvider`.

/// El único servicio que escribe `house_status`. Lo usan las escrituras que cambian el color de una
/// casa (hoy las agendas y las visitas), **dentro de su transacción**. Sin DB abierta no hay dónde
/// guardar: lanza, y quien lo lee lo traduce a un error de la pantalla.
final houseStatusUpdaterProvider = Provider<HouseStatusUpdater>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return HouseStatusUpdaterDrift(db, encolador: ref.watch(encoladorSyncProvider));
});
