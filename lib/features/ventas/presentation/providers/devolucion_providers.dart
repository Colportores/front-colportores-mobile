import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../mapa/presentation/providers/house_status_providers.dart';
import '../../data/datasources/devolucion_local_data_source_drift.dart';
import '../../data/repositories/devolucion_repository_impl.dart';
import '../../domain/repositories/devolucion_repository.dart';
import '../../domain/usecases/registrar_devolucion_use_case.dart';

// Cableado de las devoluciones (BACK-HU-VEN-004, #161). Presentation conoce domain; data se inyecta acá.

/// Guarda las devoluciones en la DB cifrada, las encola para el sync (sin dato del cliente) y recalcula
/// el color de la casa en la misma transacción. Sin DB abierta no hay dónde leer ni guardar: lanza, y
/// quien lo lee lo traduce a un error de la pantalla.
final devolucionRepositoryProvider = Provider<DevolucionRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return DevolucionRepositoryImpl(
    DevolucionLocalDataSourceDrift(
      db,
      encolador: ref.watch(encoladorSyncProvider),
      estadoDeLasCasas: ref.watch(houseStatusUpdaterProvider),
    ),
  );
});

/// Generador de UUID v7 de la devolución; un test lo reemplaza para fijar los ids.
final generadorIdDevolucionProvider = Provider<String Function()>((ref) => const Uuid().v7);

/// El reloj de la devolución (su `fecha_devolucion` y las 72 h); un test lo reemplaza.
final relojDevolucionProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// HU-VEN-004: registra la devolución de una venta.
final registrarDevolucionUseCaseProvider = Provider<RegistrarDevolucionUseCase>(
  (ref) => RegistrarDevolucionUseCase(
    ref.watch(devolucionRepositoryProvider),
    ahora: ref.watch(relojDevolucionProvider),
  ),
);
