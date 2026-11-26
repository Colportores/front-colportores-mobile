import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../cuenta/presentation/providers/cuenta_providers.dart';
import '../../../cuenta/presentation/providers/deuda_casa_providers.dart';
import '../../data/datasources/armado_del_pedido_local_drift.dart';
import '../../data/datasources/pedido_local_data_source_drift.dart';
import '../../data/repositories/pedido_repository_impl.dart';
import '../../domain/entities/armado_del_pedido.dart';
import '../../domain/entities/pedido.dart';
import '../../domain/repositories/armado_del_pedido_repository.dart';
import '../../domain/repositories/pedido_repository.dart';
import '../../domain/usecases/cancelar_pedido_use_case.dart';
import '../../domain/usecases/enviar_pedido_use_case.dart';

// Cableado de los pedidos a la casa editora (HU-STK-009, #387). Presentation conoce domain; data se inyecta
// acá.

/// Riverpod 3 reintenta solo un provider que falla (10 veces, con espera) y mientras tanto la pantalla
/// seguiría en «cargando»: las de la vista 37 muestran el error con «Reintentar» (37B·06), así que no
/// reintentan solas.
Duration? _sinReintentos(int reintentos, Object error) => null;

/// La fuente de datos de los pedidos: `pedido_casa_editora` y `pedido_item` de la DB local cifrada. Sin DB
/// abierta no hay dónde leer ni guardar: lanza, y quien lo lee lo traduce a un error de la pantalla.
final pedidoLocalProvider = Provider<PedidoLocalDataSourceDrift>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return PedidoLocalDataSourceDrift(db, encolador: ref.watch(encoladorSyncProvider));
});

/// Persistencia de los pedidos: encola el sync en la misma transacción.
final pedidoRepositoryProvider = Provider<PedidoRepository>(
  (ref) => PedidoRepositoryImpl(ref.watch(pedidoLocalProvider)),
);

/// Generador de UUID v7 del pedido y sus líneas; un test lo reemplaza para fijar los ids.
final generadorIdPedidoProvider = Provider<String Function()>((ref) => const Uuid().v7);

/// El reloj de los pedidos; un test lo reemplaza.
final relojPedidoProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Envía un pedido a la casa editora (HU-STK-009, 37A).
final enviarPedidoUseCaseProvider = Provider<EnviarPedidoUseCase>(
  (ref) => EnviarPedidoUseCase(
    ref.watch(pedidoRepositoryProvider),
    ahora: ref.watch(relojPedidoProvider),
  ),
);

/// Cancela un pedido propio que sigue por autorizar (decisión «Cancelar ped», 37B·02).
final cancelarPedidoUseCaseProvider = Provider<CancelarPedidoUseCase>(
  (ref) => CancelarPedidoUseCase(
    ref.watch(pedidoRepositoryProvider),
    ahora: ref.watch(relojPedidoProvider),
  ),
);

/// De dónde salen los productos con su costo, el stock, lo que falta entregar y el límite. Sin DB abierta,
/// nada.
final armadoDelPedidoRepositoryProvider = Provider<ArmadoDelPedidoRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return ArmadoDelPedidoLocalDrift(db);
});

/// Los pedidos de [colportorId], el más nuevo primero, cada vez que cambian. Sin DB abierta el repositorio no
/// se puede armar y el provider queda en error: las pantallas lo muestran con «Reintentar».
final pedidosProvider = StreamProvider.autoDispose.family<List<Pedido>, String>(
  (ref, colportorId) => ref.watch(pedidoRepositoryProvider).observar(colportorId),
  retry: _sinReintentos,
);

/// Los productos que se pueden pedir con lo que [colportorId] tiene de cada uno (37A·01). Sin DB, falla.
final productosPedibles = StreamProvider.autoDispose.family<List<ProductoPedible>, String>(
  (ref, colportorId) => ref.watch(armadoDelPedidoRepositoryProvider).observarProductos(colportorId),
  retry: _sinReintentos,
);

/// `id → nombre` de todos los productos, para nombrar las líneas de un pedido. Si no se pueden leer, las
/// líneas dicen «Producto»: el pedido se ve igual.
final nombresDeProductosPedidoProvider = StreamProvider.autoDispose<Map<String, String>>(
  (ref) => ref.watch(armadoDelPedidoRepositoryProvider).observarNombres(),
  retry: _sinReintentos,
);

/// Lo de la situación que sale solo de la base del teléfono (lo que falta entregar y el límite).
final contextoDelPedidoProvider = StreamProvider.autoDispose.family<ContextoLocalDelPedido, String>(
  (ref, colportorId) => ref
      .watch(armadoDelPedidoRepositoryProvider)
      .observarContexto(colportorId, ref.watch(relojPedidoProvider)()),
  retry: _sinReintentos,
);

/// La situación de [colportorId] antes de enviar: la deuda y el «Por cobrar» de Mi Cuenta (lo último que
/// bajó), más lo que falta entregar y el límite de su campaña. `loading` mientras alguna parte se lee;
/// error si la base no se pudo leer.
final situacionDelPedidoProvider = Provider.autoDispose
    .family<AsyncValue<SituacionDelColportor>, String>((ref, colportorId) {
      final resumen = ref.watch(resumenDeCuentaProvider(colportorId));
      final contexto = ref.watch(contextoDelPedidoProvider(colportorId));
      final deuda = ref.watch(deudaConLaCasaProvider(colportorId));
      if (resumen.hasError) return AsyncValue.error(resumen.error!, resumen.stackTrace!);
      if (contexto.hasError) return AsyncValue.error(contexto.error!, contexto.stackTrace!);
      if (!resumen.hasValue || !contexto.hasValue) return const AsyncValue.loading();
      final lectura = deuda.lectura;
      return AsyncValue.data(
        SituacionDelColportor(
          // Sin lectura (nada bajado todavía) o con la base de la deuda sin leer: sin cuenta no se debe
          // nada que el teléfono sepa; la hora vacía lo avisa en la pantalla.
          deudaActualCentavos: lectura?.deuda.deudaTotalCentavos ?? 0,
          porCobrarCentavos: resumen.requireValue.porCobrar.totalCentavos,
          librosPorEntregar: contexto.requireValue.librosPorEntregar,
          limiteDeudaCentavos: contexto.requireValue.limiteDeudaCentavos,
          deudaLeidaEn: lectura?.leidaEn,
        ),
      );
    });
