import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../mapa/presentation/providers/house_status_providers.dart';
import '../../data/datasources/entrega_local_data_source_drift.dart';
import '../../data/datasources/venta_local_data_source_drift.dart';
import '../../data/repositories/entrega_repository_impl.dart';
import '../../data/repositories/venta_repository_impl.dart';
import '../../data/services/fuente_de_precios_de_la_venta_sin_fuente.dart';
import '../../data/services/fuente_de_productos_de_la_entrega_sin_fuente.dart';
import '../../domain/entities/componente_vendido.dart';
import '../../domain/entities/entrega.dart';
import '../../domain/entities/linea_para_entregar.dart';
import '../../domain/entities/nueva_venta.dart';
import '../../domain/entities/precios_de_la_venta.dart';
import '../../domain/repositories/entrega_repository.dart';
import '../../domain/repositories/fuente_de_precios_de_la_venta.dart';
import '../../domain/repositories/fuente_de_productos_de_la_entrega.dart';
import '../../domain/repositories/venta_repository.dart';
import '../../domain/services/armador_de_lineas_de_entrega.dart';
import '../../domain/usecases/entregar_ahora_use_case.dart';
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

// --- Entrega inmediata (BACK-HU-VEN-002, #430; vista 27B, #432) ---

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

/// HU-VEN-002: «Entregar ahora». La pantalla 27B·01 lo usa.
final entregarAhoraUseCaseProvider = Provider<EntregarAhoraUseCase>(
  (ref) => EntregarAhoraUseCase(
    ref.watch(entregaRepositoryProvider),
    generarId: ref.watch(generadorIdVentaProvider),
    ahora: ref.watch(relojVentaProvider),
  ),
);

/// De dónde salen los nombres de lo que se vendió. Hasta que exista el adaptador del catálogo
/// (#274), no hay fuente: la pantalla lo dice y deja reintentar.
final fuenteDeProductosDeLaEntregaProvider = Provider<FuenteDeProductosDeLaEntrega>(
  (ref) => FuenteDeProductosDeLaEntregaSinFuente(),
);

/// Lo que «Entregar ahora» necesita para dibujarse: las filas de lo vendido y lo que la venta ya
/// tiene entregado (volver atrás y reentrar no entrega dos veces).
final class DatosDeLaEntrega {
  const DatosDeLaEntrega({required this.lineas, required this.nombres, required this.previas});

  final List<LineaParaEntregar> lineas;

  /// `producto.id` → nombre, para decir qué falta en el resultado.
  final Map<String, String> nombres;

  /// Las filas de entrega que la venta ya tenía; vacío si todavía no se entregó nada.
  final List<Entrega> previas;
}

/// Lee lo que vendió [guardada] y lo que ya tiene entregado. Una falla de lectura es del error
/// de la pantalla (con «Reintentar»), nunca un «no hay nada para entregar».
final datosDeLaEntregaProvider = FutureProvider.autoDispose.family<DatosDeLaEntrega, VentaGuardada>(
  (ref, guardada) async {
    final items = [
      for (final item in guardada.items)
        if (!item.estaBorrada) item,
    ];
    final previas = (await ref.watch(entregaRepositoryProvider).deLaVenta(guardada.venta.id))
        .fold<List<Entrega>>((falla) => throw falla, (filas) => filas);
    final catalogo = await ref
        .watch(fuenteDeProductosDeLaEntregaProvider)
        .leer(
          productoIds: {
            for (final item in items) ?item.productoId,
            for (final item in items)
              for (final c in item.componentes ?? const <ComponenteVendido>[]) c.productoId,
            for (final fila in previas) fila.productoId,
          },
          comboIds: {for (final item in items) ?item.coleccionId},
        );
    return catalogo.fold<DatosDeLaEntrega>(
      (falla) => throw falla,
      (productos) => DatosDeLaEntrega(
        lineas: ArmadorDeLineasDeEntrega.armar(items, productos),
        nombres: productos.nombres,
        previas: previas,
      ),
    );
  },
  retry: _sinReintentos,
);
