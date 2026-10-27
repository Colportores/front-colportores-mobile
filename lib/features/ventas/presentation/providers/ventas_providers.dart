import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../mapa/presentation/providers/house_status_providers.dart';
import '../../data/datasources/venta_local_data_source_drift.dart';
import '../../data/repositories/venta_repository_impl.dart';
import '../../data/services/fuente_de_precios_de_la_venta_sin_fuente.dart';
import '../../domain/entities/precios_de_la_venta.dart';
import '../../domain/repositories/fuente_de_precios_de_la_venta.dart';
import '../../domain/repositories/venta_repository.dart';
import '../../domain/usecases/registrar_venta_use_case.dart';

// Cableado de las ventas (BACK-HU-VEN-001, #423). Presentation conoce domain; data se inyecta acá.

/// Guarda las ventas y sus ítems en la DB cifrada, las encola para el sync (sin dato del cliente) y
/// recalcula el color de la casa en la misma transacción. Sin DB abierta no hay dónde guardar: lanza,
/// y quien lo lee lo traduce a un error de la pantalla.
final ventaRepositoryProvider = Provider<VentaRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return VentaRepositoryImpl(
    VentaLocalDataSourceDrift(
      db,
      encolador: ref.watch(encoladorSyncProvider),
      estadoDeLasCasas: ref.watch(houseStatusUpdaterProvider),
    ),
  );
});

/// Generador de UUID v7 de la venta y sus ítems; un test lo reemplaza para fijar los ids.
final generadorIdVentaProvider = Provider<String Function()>((ref) => const Uuid().v7);

/// Reloj de la venta: su `fecha` y el año del talonario. Un test lo reemplaza.
final relojVentaProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// HU-VEN-001: registrar una venta. La pantalla de la vista 27 lo usa.
final registrarVentaUseCaseProvider = Provider<RegistrarVentaUseCase>(
  (ref) => RegistrarVentaUseCase(
    ref.watch(ventaRepositoryProvider),
    generarId: ref.watch(generadorIdVentaProvider),
    ahora: ref.watch(relojVentaProvider),
  ),
);

/// De dónde sale la ciudad (y la campaña en curso) de la casa del cliente. Hasta que existan las
/// réplicas de #274, no hay fuente: la pantalla lo dice y deja reintentar.
final fuenteDePreciosDeLaVentaProvider = Provider<FuenteDePreciosDeLaVenta>(
  (ref) => FuenteDePreciosDeLaVentaSinFuente(),
);

Duration? _sinReintentos(int intento, Object error) => null;

/// Con qué precios se le vende al cliente del vínculo [espacioPersonaId] (27A·01 y 27A·10).
final preciosDeLaVentaProvider = FutureProvider.autoDispose.family<PreciosDeLaVenta, String>((
  ref,
  espacioPersonaId,
) async {
  final leido = await ref.watch(fuenteDePreciosDeLaVentaProvider).leer(espacioPersonaId);
  return leido.fold<PreciosDeLaVenta>((falla) => throw falla, (precios) => precios);
}, retry: _sinReintentos);
