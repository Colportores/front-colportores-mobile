import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/database/transaccion_local_drift.dart';
import '../../../../core/domain/transaccion_local.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../../core/usecases/use_case.dart';
import '../../../tickets/presentation/providers/tickets_providers.dart';
import '../../../ventas/domain/services/reglas_de_venta.dart';
import '../../data/datasources/campania_del_alquiler_drift.dart';
import '../../data/datasources/deposito_local_data_source_drift.dart';
import '../../data/datasources/tickets_de_deposito_sin_subir_drift.dart';
import '../../data/repositories/deposito_repository_impl.dart';
import '../../domain/repositories/deposito_repository.dart';
import '../../domain/usecases/registrar_deposito_con_ticket_use_case.dart';
import '../../domain/usecases/registrar_deposito_use_case.dart';

// Cableado de los depósitos (BACK-HU-CTA-004, #442). Presentation conoce domain; data se inyecta acá.

/// La fuente de datos de los depósitos: la tabla `deposito` de la DB local cifrada. Sin DB abierta no
/// hay dónde leer ni guardar: lanza, y quien lo lee lo traduce a un error de la pantalla.
final depositoLocalProvider = Provider<DepositoLocalDataSourceDrift>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return DepositoLocalDataSourceDrift(db, encolador: ref.watch(encoladorSyncProvider));
});

/// Persistencia de los depósitos: encola el sync en la misma transacción.
final depositoRepositoryProvider = Provider<DepositoRepository>(
  (ref) => DepositoRepositoryImpl(ref.watch(depositoLocalProvider)),
);

/// Generador de UUID v7 del depósito; un test lo reemplaza para fijar los ids.
final generadorIdDepositoProvider = Provider<String Function()>((ref) => const Uuid().v7);

/// El reloj del depósito («ahora» y la fecha máxima); un test lo reemplaza.
final relojDepositoProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Registra un depósito de efectivo (HU-CTA-004). La pantalla «Registrar depósito» (vista 33 D,
/// #443) lo usa.
final registrarDepositoUseCaseProvider = Provider<RegistrarDepositoUseCase>(
  (ref) => RegistrarDepositoUseCase(
    ref.watch(depositoRepositoryProvider),
    ahora: ref.watch(relojDepositoProvider),
  ),
);

/// La transacción de la DB local en la que el ticket del banco y su depósito entran juntos. Sin DB
/// abierta no hay dónde escribir: lanza, y la pantalla lo muestra como «no pudimos registrar».
final transaccionDeDepositoProvider = Provider<TransaccionLocal>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return TransaccionLocalDrift(db);
});

/// Registra un depósito con su ticket del banco en un solo paso, o un retiro por el coordinador sin
/// ticket (HU-CTA-004, decisión «Paso ticket»). Lo usa «Registrar depósito» (vista 33 D, #443).
final registrarDepositoConTicketUseCaseProvider = Provider<RegistrarDepositoConTicketUseCase>(
  (ref) => RegistrarDepositoConTicketUseCase(
    transaccion: ref.watch(transaccionDeDepositoProvider),
    registrarTicket: ref.watch(registrarTicketUseCaseProvider),
    registrarDeposito: ref.watch(registrarDepositoUseCaseProvider),
    almacen: ref.watch(almacenDeFotosDeTicketProvider),
    ahora: ref.watch(relojDepositoProvider),
  ),
);

/// La campaña en curso del colportor, a la que paga el alquiler; `null` si no está inscripto en
/// ninguna en curso (o no hay DB): el alquiler no se puede registrar.
final campaniaDelAlquilerProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  colportorId,
) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return null;
  final hoy = ReglasDeVenta.diaDeMontevideo(ref.watch(relojDepositoProvider)().toUtc());
  return CampaniaDelAlquilerDrift(db).leer(colportorId, hoy);
});

/// Cuántos tickets de depósito no pudieron subir su foto (vista 38A-08): pendientes después de un
/// intento fallido. Sin DB, ninguno.
final ticketsDeDepositoSinSubirProvider = StreamProvider.autoDispose<int>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return Stream.value(0);
  return TicketsDeDepositoSinSubirDrift(db).observar();
});

/// Las fechas de los depósitos cuya foto el servidor rechazó para siempre (P1 del 10/11 sobre
/// 38A-08): el aviso sin «Reintentar» que pide avisarle al coordinador. Sin DB, ninguno.
final ticketsDeDepositoRechazadosProvider = StreamProvider.autoDispose<List<DateTime>>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return Stream.value(const []);
  return TicketsDeDepositoSinSubirDrift(db).observarRechazados();
});

/// «Reintentar ahora» de 38A-08: una pasada de la cola de fotos ya, sin esperar el próximo reintento.
/// Si falla, la foto sigue pendiente y la cola la vuelve a probar sola. Un test lo reemplaza.
final reintentarSubidaDeTicketsProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    await ref.read(subirFotosDeTicketsUseCaseProvider)(const NoParams());
  };
});
