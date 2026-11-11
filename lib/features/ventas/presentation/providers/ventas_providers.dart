import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../mapa/presentation/providers/house_status_providers.dart';
import '../../data/datasources/personas_para_vender_drift.dart';
import '../../data/datasources/venta_local_data_source_drift.dart';
import '../../data/repositories/venta_repository_impl.dart';
import '../../data/services/fuente_de_precios_de_la_venta_local.dart';
import '../../data/services/fuente_de_precios_de_la_venta_sin_fuente.dart';
import '../../domain/entities/persona_para_vender.dart';
import '../../domain/entities/precios_de_la_venta.dart';
import '../../domain/repositories/fuente_de_precios_de_la_venta.dart';
import '../../domain/repositories/lector_de_personas_para_vender.dart';
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

/// De dónde sale la ciudad (y la campaña en curso) de la casa del cliente: la casa y las réplicas del
/// pull de catálogos, en el teléfono y sin red (la misma fuente de la vista 26). Sin la base abierta
/// no se sabe: la pantalla lo dice y deja reintentar.
final fuenteDePreciosDeLaVentaProvider = Provider<FuenteDePreciosDeLaVenta>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return FuenteDePreciosDeLaVentaSinFuente();
  return FuenteDePreciosDeLaVentaLocal(db, ahora: ref.watch(relojVentaProvider));
});

Duration? _sinReintentos(int intento, Object error) => null;

/// A quién y quién vende: la clave de [preciosDeLaVentaProvider].
typedef ClienteYColportor = ({String colportorId, String espacioPersonaId});

/// Con qué precios [ClienteYColportor.colportorId] le vende al cliente del vínculo
/// [ClienteYColportor.espacioPersonaId] (27A·01 y 27A·10).
final preciosDeLaVentaProvider = FutureProvider.autoDispose
    .family<PreciosDeLaVenta, ClienteYColportor>((ref, clave) async {
      final leido = await ref
          .watch(fuenteDePreciosDeLaVentaProvider)
          .leer(colportorId: clave.colportorId, espacioPersonaId: clave.espacioPersonaId);
      return leido.fold<PreciosDeLaVenta>((falla) => throw falla, (precios) => precios);
    }, retry: _sinReintentos);

/// Lo que «Cobrar ahora» de 27A·14 le pasa al cobro (vista 28): la venta recién registrada y con quién
/// y dónde fue. `colportorId` es el usuario con la sesión iniciada.
typedef ContextoDeCobroDeLaVenta = ({
  String ventaId,
  String espacioId,
  String? espacioPersonaId,
  String colportorId,
});

/// A dónde lleva «Cobrar ahora» de «Venta registrada: ¿y ahora?» (27A·14): abre el cobro en efectivo
/// (vista 28, #439) y devuelve `true` si se cobró. `null` = el cobro no está enganchado: la pantalla
/// no dibuja el grupo COBRO, porque un botón que no lleva a ningún lado sería mentir (decisión del
/// 27/10, P7 de #158). Quien monta `VentaRegistradaPage` pasa `conCobro: ref.read(...) != null`.
final cobrarDespuesDeLaVentaProvider = Provider<Future<bool> Function(ContextoDeCobroDeLaVenta)?>(
  (ref) => null,
);

/// Lee del teléfono las personas a las que se les puede vender desde la pestaña Ventas (#546). Sin DB
/// abierta no hay qué leer: lanza, y quien lo lee lo traduce a un error de la pantalla.
final lectorDePersonasParaVenderProvider = Provider<LectorDePersonasParaVender>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return PersonasParaVenderDrift(db);
});

/// Las personas del colportor [colportorId] a las que se les puede vender, en vivo: sale de «+
/// Registrar venta» de la pestaña Ventas.
final personasParaVenderProvider = StreamProvider.autoDispose
    .family<List<PersonaParaVender>, String>(
      (ref, colportorId) => ref.watch(lectorDePersonasParaVenderProvider).observar(colportorId),
      retry: _sinReintentos,
    );
