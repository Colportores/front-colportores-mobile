import 'package:dartz/dartz.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../../datos/drift_sync_meta.dart';
import '../../../ventas/domain/services/reglas_de_venta.dart';
import '../../data/datasources/materiales_local_data_source_drift.dart';
import '../../data/datasources/transferencia_local_data_source_drift.dart';
import '../../data/repositories/companieros_de_campania_local.dart';
import '../../data/repositories/companieros_de_campania_sin_fuente.dart';
import '../../data/repositories/transferencia_repository_impl.dart';
import '../../domain/entities/companiero_de_campania.dart';
import '../../domain/entities/material_de_transferencia.dart';
import '../../domain/entities/transferencia.dart';
import '../../domain/repositories/companieros_de_campania_repository.dart';
import '../../domain/repositories/transferencia_repository.dart';
import '../../domain/usecases/cancelar_transferencia_use_case.dart';
import '../../domain/usecases/pedir_transferencia_use_case.dart';

// Cableado de las transferencias de materiales (HU-STK-005, #512). Presentation conoce domain; data se
// inyecta acá.

/// Riverpod 3 reintenta solo un provider que falla (10 veces, con espera) y mientras tanto la pantalla
/// seguiría en «cargando»: las de la vista 40 muestran el error con «Reintentar» (40B·10), así que no
/// reintentan solas.
Duration? _sinReintentos(int reintentos, Object error) => null;

/// La fuente de datos de las transferencias: las tablas `transferencia_stock` y `transferencia_item` de la
/// DB local cifrada. Sin DB abierta no hay dónde leer ni guardar: lanza, y quien lo lee lo traduce a un
/// error de la pantalla.
final transferenciaLocalProvider = Provider<TransferenciaLocalDataSourceDrift>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return TransferenciaLocalDataSourceDrift(db, encolador: ref.watch(encoladorSyncProvider));
});

/// Persistencia de las transferencias: encola el sync en la misma transacción.
final transferenciaRepositoryProvider = Provider<TransferenciaRepository>(
  (ref) => TransferenciaRepositoryImpl(ref.watch(transferenciaLocalProvider)),
);

/// Generador de UUID v7 de la transferencia y sus líneas; un test lo reemplaza para fijar los ids.
final generadorIdTransferenciaProvider = Provider<String Function()>((ref) => const Uuid().v7);

/// El reloj de las transferencias; un test lo reemplaza.
final relojTransferenciaProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Pide una transferencia de materiales (HU-STK-005, 40A).
final pedirTransferenciaUseCaseProvider = Provider<PedirTransferenciaUseCase>(
  (ref) => PedirTransferenciaUseCase(
    ref.watch(transferenciaRepositoryProvider),
    ahora: ref.watch(relojTransferenciaProvider),
  ),
);

/// Cancela una transferencia propia que sigue por autorizar (decisión «Cancelar tr.», 40B·03).
final cancelarTransferenciaUseCaseProvider = Provider<CancelarTransferenciaUseCase>(
  (ref) => CancelarTransferenciaUseCase(
    ref.watch(transferenciaRepositoryProvider),
    ahora: ref.watch(relojTransferenciaProvider),
  ),
);

/// Las transferencias de [colportorId] (las dos puntas), la más nueva primero, cada vez que cambian. Sin
/// DB abierta, el error de lectura.
final transferenciasProvider = StreamProvider.autoDispose.family<List<Transferencia>, String>((
  ref,
  colportorId,
) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return Stream.error(const FailureTransferenciasNoDisponibles());
  return ref.watch(transferenciaRepositoryProvider).observar(colportorId);
}, retry: _sinReintentos);

/// Los materiales que se pueden pedir y lo que [colportorId] tiene de cada uno (40A·01). Sin DB, ninguno.
final materialesDeTransferenciaProvider = StreamProvider.autoDispose
    .family<List<MaterialDeTransferencia>, String>((ref, colportorId) {
      final db = ref.watch(dbLocalProvider);
      if (db == null) return Stream.value(const []);
      return MaterialesLocalDataSourceDrift(db).observar(colportorId);
    }, retry: _sinReintentos);

/// `id → nombre` de todos los productos, para nombrar las líneas de una transferencia. Sin DB, vacío.
final nombresDeProductosProvider = StreamProvider.autoDispose<Map<String, String>>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return Stream.value(const {});
  return MaterialesLocalDataSourceDrift(db).observarNombres();
}, retry: _sinReintentos);

/// De dónde salen los colportores de la campaña (40A·02): la tabla `campania_companiero` del teléfono
/// (los nombres que baja el servidor, «Nombres camp.», #769). Sin DB, [CompanierosDeCampaniaSinFuente]:
/// la pantalla dice que no pudo traerlos.
final companierosDeCampaniaRepositoryProvider = Provider<CompanierosDeCampaniaRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return const CompanierosDeCampaniaSinFuente();
  final reloj = ref.watch(relojTransferenciaProvider);
  return CompanierosDeCampaniaLocal(db, () => ReglasDeVenta.diaDeMontevideo(reloj().toUtc()));
});

/// Los compañeros de campaña de [colportorId]: la lista o por qué no se pudo traer. Sirve también para
/// poner nombre a la otra punta de cada transferencia.
final companierosDeCampaniaProvider = FutureProvider.autoDispose
    .family<Either<Failure, CompanierosDeCampania>, String>(
      (ref, colportorId) => ref.watch(companierosDeCampaniaRepositoryProvider).listar(colportorId),
      retry: _sinReintentos,
    );

/// La última vez que el teléfono bajó datos del servidor (40B·11, «como estaban ayer a las 21:00»), o
/// `null` si todavía no bajó nada. Sin DB, `null`.
final ultimaBajadaDeTransferenciasProvider = FutureProvider.autoDispose<DateTime?>((ref) async {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return null;
  return (await DriftSyncMeta(db).read()).lastPullAt;
}, retry: _sinReintentos);

/// «Hacer un pedido» a la casa editora (vista 37, #387), a donde manda 40A·09 («No hay otro colportor en
/// tu campaña»). `null` mientras esa pantalla no exista en la app: entonces 40A·09 solo ofrece volver.
/// `main.dart` lo engancha cuando llegue.
final hacerUnPedidoDesdeTransferenciaProvider = Provider<void Function(BuildContext)?>(
  (ref) => null,
);
