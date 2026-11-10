import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../data/datasources/cuenta_de_persona_local_data_source_drift.dart';
import '../../data/services/cuenta_de_persona_drift.dart';
import '../../domain/entities/persona_del_espacio.dart';
import '../../domain/services/cuenta_de_persona.dart';
import '../../domain/usecases/baja_persona_use_cases.dart';
import 'personas_providers.dart';

// Cableado de la baja de una persona y de «Ver bajas» (HU-UBI-011, vista 32D). Todo es local: la
// persona no se sincroniza y la baja tampoco. El repositorio, el reloj y el saldo de cada persona son
// los de `personas_providers.dart`.

/// Riverpod 3 reintenta 10 veces lo que falla: la pantalla muestra el error enseguida y el
/// «Reintentar» es de quien lo toca.
Duration? _sinReintentos(int intento, Object error) => null;

/// Lo que la DB local sabe de las entregas, los cobros y la cuenta de una persona (la ficha, 32B, y la
/// baja con saldo, 32D·02). Sin DB abierta no hay dónde leer: lanza, y la pantalla lo muestra como un
/// error de lectura.
final cuentaDePersonaLocalProvider = Provider<CuentaDePersonaLocalDataSourceDrift>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return CuentaDePersonaLocalDataSourceDrift(db);
});

/// De dónde sale la cuenta de cada persona (comprado, entregado, pagado y saldo de la ficha y de la baja
/// con saldo, 32D·02): las ventas, las entregas y los cobros del teléfono, nunca el servidor (ADR-004).
/// Un test lo reemplaza con un fake.
final cuentasDePersonasProvider = Provider<CuentasDePersonas>(
  (ref) => CuentasDePersonasDrift(ref.watch(cuentaDePersonaLocalProvider)),
);

final consultarCuentaDePersonaUseCaseProvider = Provider<ConsultarCuentaDePersonaUseCase>(
  (ref) => ConsultarCuentaDePersonaUseCase(ref.watch(cuentasDePersonasProvider)),
);

final darDeBajaPersonaUseCaseProvider = Provider<DarDeBajaPersonaUseCase>(
  (ref) => DarDeBajaPersonaUseCase(
    ref.watch(personaRepositoryProvider),
    ref.watch(cuentasDePersonasProvider),
    ahora: ref.watch(relojPersonaProvider),
  ),
);

final reactivarPersonaUseCaseProvider = Provider<ReactivarPersonaUseCase>(
  (ref) => ReactivarPersonaUseCase(
    ref.watch(personaRepositoryProvider),
    ahora: ref.watch(relojPersonaProvider),
  ),
);

/// Las personas dadas de baja de [espacioId], la baja más reciente primero, al día cuando se da de baja
/// o se reactiva una. Una falla de lectura es el error del provider.
final bajasDelEspacioProvider = StreamProvider.autoDispose.family<List<PersonaDelEspacio>, String>(
  (ref, espacioId) => ref.watch(personaRepositoryProvider).observarBajasDelEspacio(espacioId),
  retry: _sinReintentos,
);

/// Lo que debe cada persona dada de baja de [espacioId], en centavos, por `persona.id` («Baja el 22/10 ·
/// saldo $ 1.200»). Una falla al leerlo no frena la lista: la fila queda sin saldo (no se afirma lo que
/// no se sabe).
final saldosDeBajasDelEspacioProvider = FutureProvider.autoDispose.family<Map<String, int>, String>(
  (ref, espacioId) async {
    final bajas = await ref.watch(bajasDelEspacioProvider(espacioId).future);
    if (bajas.isEmpty) return const {};
    try {
      return await ref
          .watch(saldosDePersonasProvider)
          .saldosPendientes(bajas.map((p) => p.persona.id));
    } on Object {
      return const {};
    }
  },
  retry: _sinReintentos,
);
