import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../data/datasources/persona_local_data_source_drift.dart';
import '../../data/datasources/ubicacion_local_data_source_drift.dart';
import '../../data/datasources/ultima_visita_del_espacio_drift.dart';
import '../../data/repositories/espacio_repository_impl.dart';
import '../../data/repositories/persona_repository_impl.dart';
import '../../domain/entities/contexto_edicion_persona.dart';
import '../../domain/entities/persona_del_espacio.dart';
import '../../domain/entities/ultima_visita_del_espacio.dart';
import '../../domain/repositories/espacio_repository.dart';
import '../../domain/repositories/persona_repository.dart';
import '../../domain/services/contador_personas_espacio.dart';
import '../../domain/services/criterio_otra_persona.dart';
import '../../domain/services/lector_ultima_visita_del_espacio.dart';
import '../../domain/services/saldos_de_personas.dart';
import '../../domain/usecases/modificar_persona_use_case.dart';
import '../../domain/usecases/registrar_persona_use_case.dart';

// Cableado de las personas de un espacio (HU-UBI-008, vistas 32A y 11·04). Presentation conoce domain;
// data se inyecta acá. Todo es local: la persona y sus notas no se sincronizan, y el vínculo con el
// espacio sube solo con ids (ADR-017) por el motor, que es el que ya cablea `encoladorSyncProvider`.

/// La DB local abierta (`dbLocalProvider`). Sin DB abierta no hay dónde guardar: lanza, y quien lo lee
/// lo traduce a un error de la pantalla.
final espacioRepositoryProvider = Provider<EspacioRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return EspacioRepositoryImpl(
    UbicacionLocalDataSourceDrift(db, encolador: ref.watch(encoladorSyncProvider)),
  );
});

final _personaLocalProvider = Provider<PersonaLocalDataSourceDrift>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return PersonaLocalDataSourceDrift(db, encolador: ref.watch(encoladorSyncProvider));
});

final personaRepositoryProvider = Provider<PersonaRepository>(
  (ref) => PersonaRepositoryImpl(ref.watch(_personaLocalProvider)),
);

/// Cuántas personas activas tiene un espacio: el adaptador real del puerto de la baja de espacios
/// (HU-UBI-007), que hasta ahora solo tenía un fake.
final contadorPersonasEspacioProvider = Provider<ContadorPersonasEspacio>(
  (ref) => ref.watch(_personaLocalProvider),
);

/// Generador de UUID v7 del alta de una persona; un test lo reemplaza para fijar los ids.
final generadorIdPersonaProvider = Provider<String Function()>((ref) => const Uuid().v7);

/// Reloj del alta de una persona; un test lo reemplaza.
final relojPersonaProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final registrarPersonaUseCaseProvider = Provider<RegistrarPersonaUseCase>(
  (ref) => RegistrarPersonaUseCase(
    ref.watch(personaRepositoryProvider),
    generarId: ref.watch(generadorIdPersonaProvider),
    ahora: ref.watch(relojPersonaProvider),
  ),
);

final modificarPersonaUseCaseProvider = Provider<ModificarPersonaUseCase>(
  (ref) => ModificarPersonaUseCase(
    ref.watch(personaRepositoryProvider),
    ahora: ref.watch(relojPersonaProvider),
  ),
);

/// Cuándo un cambio a una persona parece «otra persona» (HU-UBI-010, canvas 32C·03): la regla que
/// decidió Cristian el 27/10, [CriterioOtraPersonaPorNombreYApellido]. Un test lo reemplaza.
final criterioOtraPersonaProvider = Provider<CriterioOtraPersona>(
  (ref) => const CriterioOtraPersonaPorNombreYApellido(),
);

/// Riverpod 3 reintenta 10 veces lo que falla: la pantalla muestra el error enseguida y el
/// «Reintentar» es de quien lo toca.
Duration? _sinReintentos(int intento, Object error) => null;

/// La persona [personaId] como está hoy en el teléfono y si se la puede editar, o `null` si ya no está.
/// Una falla de lectura es el error del provider.
final contextoEdicionPersonaProvider = FutureProvider.autoDispose
    .family<ContextoEdicionPersona?, String>((ref, personaId) async {
      final lectura = await ref.watch(personaRepositoryProvider).leerParaEditar(personaId);
      return lectura.fold((Failure falla) => throw falla, (contexto) => contexto);
    }, retry: _sinReintentos);

/// El espacio [espacioId] con su ubicación, o `null` si ya no está en el teléfono. Una falla de
/// lectura sale como error del provider.
final contextoEspacioProvider = FutureProvider.autoDispose.family<EspacioConUbicacion?, String>((
  ref,
  espacioId,
) async {
  final lectura = await ref.watch(espacioRepositoryProvider).buscar(espacioId);
  return lectura.fold((Failure falla) => throw falla, (contexto) => contexto);
});

/// Las personas activas de [espacioId], al día cuando se agrega o se da de baja una.
final personasDelEspacioProvider = StreamProvider.autoDispose
    .family<List<PersonaDelEspacio>, String>(
      (ref, espacioId) => ref.watch(personaRepositoryProvider).observarDelEspacio(espacioId),
    );

/// De dónde sale la última visita de un espacio (el estado del encabezado de la ficha del depto, vista
/// 11·04, #151). Sin la DB local abierta no hay de dónde: lanza, y quien lo lee no dice ningún estado.
final lectorUltimaVisitaDelEspacioProvider = Provider<LectorUltimaVisitaDelEspacio>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return UltimaVisitaDelEspacioDrift(db);
});

/// La última visita de [espacioId], al día cuando se registra o se deshace una; `null` si no tiene
/// ninguna. Una falla de lectura sale como error del provider (el encabezado no afirma nada).
final ultimaVisitaDelEspacioProvider = StreamProvider.autoDispose
    .family<UltimaVisitaDelEspacio?, String>(
      (ref, espacioId) => ref.watch(lectorUltimaVisitaDelEspacioProvider).observar(espacioId),
      retry: _sinReintentos,
    );

/// De dónde sale lo que debe cada persona (la línea «Saldo» de «¿Con quién?»). Sin ventas locales
/// todavía (S9) no hay fuente: [SaldosDePersonasSinFuente]. Un test o el S9 lo reemplazan.
final saldosDePersonasProvider = Provider<SaldosDePersonas>(
  (ref) => const SaldosDePersonasSinFuente(),
);

/// Lo que debe cada persona de [espacioId], en centavos, por `persona.id`. Una falla al leerlo no
/// frena el paso: la fila queda sin saldo (no se afirma lo que no se sabe) y se puede elegir igual.
final saldosDelEspacioProvider = FutureProvider.autoDispose.family<Map<String, int>, String>((
  ref,
  espacioId,
) async {
  final personas = await ref.watch(personasDelEspacioProvider(espacioId).future);
  try {
    return await ref
        .watch(saldosDePersonasProvider)
        .saldosPendientes(personas.map((p) => p.persona.id));
  } on Object {
    return const {};
  }
});
