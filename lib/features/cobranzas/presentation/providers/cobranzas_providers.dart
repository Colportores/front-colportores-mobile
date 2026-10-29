import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../mapa/domain/services/saldos_de_personas.dart';
import '../../../mapa/presentation/providers/house_status_providers.dart';
import '../../data/datasources/cobranza_local_data_source_drift.dart';
import '../../data/repositories/cobranza_repository_impl.dart';
import '../../domain/repositories/cobranza_repository.dart';
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
