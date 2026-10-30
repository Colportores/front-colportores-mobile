import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../agenda/presentation/providers/recordatorios_providers.dart';
import '../../../mapa/domain/services/saldos_de_personas.dart';
import '../../../mapa/presentation/providers/house_status_providers.dart';
import '../../data/datasources/cobranza_local_data_source_drift.dart';
import '../../data/datasources/cuotas_local_data_source_drift.dart';
import '../../data/repositories/cobranza_repository_impl.dart';
import '../../data/repositories/plan_de_cuotas_repository_impl.dart';
import '../../data/repositories/saldo_pendiente_repository_impl.dart';
import '../../domain/entities/cuota.dart';
import '../../domain/entities/venta_con_saldo.dart';
import '../../domain/repositories/cobranza_repository.dart';
import '../../domain/repositories/plan_de_cuotas_repository.dart';
import '../../domain/repositories/saldo_pendiente_repository.dart';
import '../../domain/usecases/armar_plan_de_cuotas_use_case.dart';
import '../../domain/usecases/modificar_cuotas_use_case.dart';
import '../../domain/usecases/registrar_cobro_use_case.dart';

// Cableado de los cobros (BACK-HU-COB-001, #436). Presentation conoce domain; data se inyecta acá.

/// La fuente de datos de los cobros: las tablas `cobranza` y `venta` de la DB local cifrada. Sin DB
/// abierta no hay dónde leer ni guardar: lanza, y quien lo lee lo traduce a un error de la pantalla.
final cobranzaLocalProvider = Provider<CobranzaLocalDataSourceDrift>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return CobranzaLocalDataSourceDrift(
    db,
    encolador: ref.watch(encoladorSyncProvider),
    estadoDeLasCasas: ref.watch(houseStatusUpdaterProvider),
  );
});

/// Persistencia de los cobros: encola el sync y recalcula el color de la casa en la misma
/// transacción.
final cobranzaRepositoryProvider = Provider<CobranzaRepository>(
  (ref) => CobranzaRepositoryImpl(ref.watch(cobranzaLocalProvider)),
);

/// Generador de UUID v7 del cobro; un test lo reemplaza para fijar los ids.
final generadorIdCobroProvider = Provider<String Function()>((ref) => const Uuid().v7);

/// El reloj del cobro («hoy» y la fecha máxima); un test lo reemplaza.
final relojCobroProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Registra el cobro de una venta, en efectivo, con tarjeta o por transferencia (HU-COB-001, HU-COB-002 y
/// HU-COB-003).
final registrarCobroUseCaseProvider = Provider<RegistrarCobroUseCase>(
  (ref) => RegistrarCobroUseCase(
    ref.watch(cobranzaRepositoryProvider),
    ahora: ref.watch(relojCobroProvider),
  ),
);

/// Lo que debe cada persona, sumando el saldo de sus ventas vivas (la línea «Saldo» de «¿Con quién?»
/// y el monto de «$ Cobrar»). Local: sale de las ventas y cobros del teléfono, nunca del servidor.
final class SaldosDePersonasLocal implements SaldosDePersonas {
  const SaldosDePersonasLocal(this._local);

  final CobranzaLocalDataSourceDrift _local;

  @override
  Future<Map<String, int>> saldosPendientes(Iterable<String> personaIds) =>
      _local.saldosPorPersona(personaIds);
}

// Saldo pendiente reactivo (HU-COB-005): lo que se debe por venta, por persona, por ubicación y en
// total, al día solo después de cada cobro.

/// Sin reintentos: un `Stream` que falla (la base no se pudo leer) deja el error a la vista en vez de
/// quedarse en «cargando» (Riverpod 3 reintenta 10 veces).
Duration? _sinReintentos(int intento, Object error) => null;

/// De dónde sale el saldo: las tablas `venta` y `cobranza` de la DB local. Sin DB abierta, sus
/// `Stream` fallan con `FailureSaldoNoDisponible`.
final saldoPendienteRepositoryProvider = Provider<SaldoPendienteRepository>((ref) {
  if (ref.watch(dbLocalProvider) == null) return const SaldoPendienteSinBase();
  return SaldoPendienteRepositoryImpl(ref.watch(cobranzaLocalProvider));
});

/// La venta con lo cobrado y lo que debe; `null` si no está o se dio de baja.
final saldoDeLaVentaProvider = StreamProvider.autoDispose.family<VentaConSaldo?, String>(
  (ref, ventaId) => ref.watch(saldoPendienteRepositoryProvider).observarVenta(ventaId),
  retry: _sinReintentos,
);

/// Lo que debe la persona (centavos), sumando sus ventas vivas.
final saldoDeLaPersonaProvider = StreamProvider.autoDispose.family<int, String>(
  (ref, personaId) => ref.watch(saldoPendienteRepositoryProvider).observarDePersona(personaId),
  retry: _sinReintentos,
);

/// Lo que se debe en la ubicación (centavos), sumando las ventas de las personas de todos sus
/// espacios.
final saldoDeLaUbicacionProvider = StreamProvider.autoDispose.family<int, String>(
  (ref, ubicacionId) =>
      ref.watch(saldoPendienteRepositoryProvider).observarDeUbicacion(ubicacionId),
  retry: _sinReintentos,
);

/// Lo que le deben al colportor (centavos) en total, sumando todas sus ventas vivas.
final saldoTotalDelColportorProvider = StreamProvider.autoDispose.family<int, String>(
  (ref, colportorId) => ref.watch(saldoPendienteRepositoryProvider).observarTotal(colportorId),
  retry: _sinReintentos,
);

// Plan de cuotas (HU-COB-004, #399): cada cuota es una cita de cobranza con su venta y su monto.

/// El plan de cuotas de una venta en la DB local: las citas de cobranza con monto, sus cobros y su
/// saldo. Sin DB abierta no hay dónde leer ni guardar: lanza, y quien lo lee lo traduce a un error de
/// la pantalla.
final planDeCuotasRepositoryProvider = Provider<PlanDeCuotasRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return PlanDeCuotasRepositoryImpl(
    CuotasLocalDataSourceDrift(
      db,
      encolador: ref.watch(encoladorSyncProvider),
      estadoDeLasCasas: ref.watch(houseStatusUpdaterProvider),
    ),
  );
});

/// Arma el plan de cuotas de una venta (vista 30 A, 30A-01 a 30A-08).
final armarPlanDeCuotasUseCaseProvider = Provider<ArmarPlanDeCuotasUseCase>(
  (ref) => ArmarPlanDeCuotasUseCase(
    ref.watch(planDeCuotasRepositoryProvider),
    ref.watch(recordatoriosProvider),
    ahora: ref.watch(relojCobroProvider),
  ),
);

/// Modifica las cuotas que no están cerradas (30A-09).
final modificarCuotasUseCaseProvider = Provider<ModificarCuotasUseCase>(
  (ref) => ModificarCuotasUseCase(
    ref.watch(planDeCuotasRepositoryProvider),
    ahora: ref.watch(relojCobroProvider),
  ),
);

/// El plan de la venta con sus cuotas al día después de cada cobro, cada alta y cada cancelación;
/// `null` si la venta no está o se dio de baja. Si no se puede leer, falla con
/// `FailureCuotasNoDisponibles` (no se lee como «sin plan»).
final planDeLaVentaProvider = StreamProvider.autoDispose.family<PlanDeCuotas?, String>((
  ref,
  ventaId,
) {
  final PlanDeCuotasRepository repositorio;
  try {
    repositorio = ref.watch(planDeCuotasRepositoryProvider);
  } on StateError {
    return Stream<PlanDeCuotas?>.error(const FailureCuotasNoDisponibles());
  }
  return repositorio.observar(ventaId);
}, retry: _sinReintentos);
