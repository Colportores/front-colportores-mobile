import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../data/datasources/deposito_local_data_source_drift.dart';
import '../../data/repositories/deposito_repository_impl.dart';
import '../../domain/repositories/deposito_repository.dart';
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
