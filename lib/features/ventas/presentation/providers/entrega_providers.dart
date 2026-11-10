import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../agenda/presentation/providers/recordatorios_providers.dart';
import '../../../mapa/presentation/providers/house_status_providers.dart';
import '../../data/datasources/entrega_local_data_source_drift.dart';
import '../../data/repositories/entrega_repository_impl.dart';
import '../../data/services/fuente_de_productos_de_la_entrega_local.dart';
import '../../data/services/fuente_de_productos_de_la_entrega_sin_fuente.dart';
import '../../domain/entities/componente_vendido.dart';
import '../../domain/entities/entrega.dart';
import '../../domain/entities/entrega_pendiente.dart';
import '../../domain/entities/linea_para_entregar.dart';
import '../../domain/entities/nueva_venta.dart';
import '../../domain/repositories/entrega_repository.dart';
import '../../domain/repositories/fuente_de_productos_de_la_entrega.dart';
import '../../domain/services/armador_de_lineas_de_entrega.dart';
import '../../domain/usecases/cumplir_entrega_use_case.dart';
import '../../domain/usecases/diferir_entrega_use_case.dart';
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
    recordatorios: ref.watch(recordatoriosProvider),
  ),
);

// --- Entrega diferida (BACK-HU-VEN-003, #433; vista 27C, #435) ---

/// HU-VEN-003, «Entrega diferida»: deja lo que falta entregar para otra fecha, con su cita y su
/// recordatorio en la agenda. La vista 27C-01 y «Poner fecha» (27C-02) lo usan.
final diferirEntregaUseCaseProvider = Provider<DiferirEntregaUseCase>(
  (ref) => DiferirEntregaUseCase(
    ref.watch(entregaRepositoryProvider),
    ref.watch(recordatoriosProvider),
    generarId: ref.watch(generadorIdEntregaProvider),
    ahora: ref.watch(relojEntregaProvider),
  ),
);

/// HU-VEN-003, «Cumplir entrega pendiente»: «Marcar entregado» (27C-03 y 27C-04).
final cumplirEntregaUseCaseProvider = Provider<CumplirEntregaUseCase>(
  (ref) => CumplirEntregaUseCase(
    ref.watch(entregaRepositoryProvider),
    ref.watch(recordatoriosProvider),
    generarId: ref.watch(generadorIdEntregaProvider),
    ahora: ref.watch(relojEntregaProvider),
  ),
);

/// Todo lo que falta entregar, una entrada por venta (27C-02 «Entregas pendientes»). Reactivo y solo
/// del teléfono: se repinta cuando se deja una entrega, se marca o se mueve su fecha.
final entregasPendientesProvider = StreamProvider.autoDispose<List<EntregaPendiente>>(
  (ref) => ref.watch(entregaRepositoryProvider).observarPendientes(),
);

/// Lo que falta entregarle a la persona del vínculo [espacioPersonaId] (su ficha, vista 32).
final entregasPendientesDeProvider = StreamProvider.autoDispose
    .family<List<EntregaPendiente>, String>(
      (ref, espacioPersonaId) => ref
          .watch(entregaRepositoryProvider)
          .observarPendientes(espacioPersonaId: espacioPersonaId),
    );

// --- La pantalla «Entregar ahora» (vista 27B, #432) ---

/// Sin reintentos automáticos: una falla de lectura es de la pantalla (con «Reintentar»).
Duration? _sinReintentos(int intento, Object error) => null;

/// De dónde salen los nombres de lo que se vendió: la réplica local del catálogo, sin red. Sin la
/// base abierta no se sabe: la pantalla lo dice y deja reintentar.
final fuenteDeProductosDeLaEntregaProvider = Provider<FuenteDeProductosDeLaEntrega>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return FuenteDeProductosDeLaEntregaSinFuente();
  return FuenteDeProductosDeLaEntregaLocal(db);
});

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
