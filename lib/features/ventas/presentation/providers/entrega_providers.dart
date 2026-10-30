import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../mapa/presentation/providers/house_status_providers.dart';
import '../../data/datasources/entrega_local_data_source_drift.dart';
import '../../data/repositories/entrega_repository_impl.dart';
import '../../domain/repositories/entrega_repository.dart';
import '../../domain/usecases/entregar_ahora_use_case.dart';

// Cableado de las entregas (BACK-HU-VEN-002, #430). Presentation conoce domain; data se inyecta acá.

/// Guarda las entregas en la DB cifrada, las encola para el sync (sin dato del cliente) y recalcula el
/// color de la casa en la misma transacción. Sin DB abierta no hay dónde guardar: lanza, y quien lo
/// lee lo traduce a un error de la pantalla.
final entregaRepositoryProvider = Provider<EntregaRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return EntregaRepositoryImpl(
    EntregaLocalDataSourceDrift(
      db,
      encolador: ref.watch(encoladorSyncProvider),
      estadoDeLasCasas: ref.watch(houseStatusUpdaterProvider),
    ),
  );
});

/// Generador de UUID v7 de las filas de entrega; un test lo reemplaza para fijar los ids.
final generadorIdEntregaProvider = Provider<String Function()>((ref) => const Uuid().v7);

/// El reloj de la entrega (su `fecha_entrega`); un test lo reemplaza.
final relojEntregaProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// HU-VEN-002: «Entregar ahora». La pantalla de la entrega (#432) lo usa.
final entregarAhoraUseCaseProvider = Provider<EntregarAhoraUseCase>(
  (ref) => EntregarAhoraUseCase(
    ref.watch(entregaRepositoryProvider),
    generarId: ref.watch(generadorIdEntregaProvider),
    ahora: ref.watch(relojEntregaProvider),
  ),
);
