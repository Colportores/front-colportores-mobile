import 'dart:async';

import 'package:flutter/widgets.dart' show BuildContext, Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../data/datasources/entrevistas_de_personas_local_data_source_drift.dart';
import '../../data/datasources/nota_del_lugar_local_data_source_drift.dart';
import '../../domain/entities/contexto_de_la_casa.dart';
import '../../domain/entities/persona_de_la_entrevista.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/services/lector_entrevistas_de_personas.dart';
import '../../domain/services/lector_notas_del_lugar.dart';
import '../../domain/usecases/observar_contexto_de_la_casa_use_case.dart';
import 'personas_providers.dart';

// Cableado de la hoja de la casa (vista 39, C·01): qué lee (el espacio, las personas, lo que deben y
// la nota del lugar) y los dos enganches hacia las vistas hijas que todavía no existen.

/// Las notas del lugar de la DB local (`nota` con `target_type = UBICACION`). Sin DB abierta no hay
/// dónde leer: lanza, y la hoja lo muestra como «No pudimos leer esta casa en tu teléfono.».
final lectorNotasDelLugarProvider = Provider<LectorNotasDelLugar>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return NotaDelLugarLocalDataSourceDrift(db);
});

/// Las visitas de entrevista de la DB local (`visita`), de donde sale «Entrevista dada el 05/10» de
/// cada persona. Sin DB abierta no hay dónde leer: lanza, y la hoja lo muestra como «No pudimos leer
/// esta casa en tu teléfono.».
final lectorEntrevistasDePersonasProvider = Provider<LectorEntrevistasDePersonas>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return EntrevistasDePersonasLocalDataSourceDrift(db);
});

final observarContextoDeLaCasaUseCaseProvider = Provider<ObservarContextoDeLaCasaUseCase>(
  (ref) => ObservarContextoDeLaCasaUseCase(
    espacios: ref.watch(espacioRepositoryProvider),
    personas: ref.watch(personaRepositoryProvider),
    saldos: ref.watch(saldosDePersonasProvider),
    notas: ref.watch(lectorNotasDelLugarProvider),
    entrevistas: ref.watch(lectorEntrevistasDePersonasProvider),
  ),
);

/// Riverpod 3 reintenta 10 veces lo que falla: la hoja muestra el error enseguida (E·02) y el
/// «Reintentar» es de quien lo toca.
Duration? _sinReintentos(int intento, Object error) => null;

/// Qué ubicación lee la hoja: su `id` y su tipo (que decide si hay un solo espacio o un depto por
/// elegir). Editar la dirección no cambia la clave: la hoja no vuelve a «cargando».
typedef ClaveDeLaCasa = ({String ubicacionId, TipoUbicacion tipo});

/// Lo que la hoja de la casa [clave] muestra además de la ubicación: su espacio, las personas, lo que
/// deben y la nota más reciente. Una falla de lectura es el error del provider.
final contextoDeLaCasaProvider = StreamProvider.autoDispose.family<ContextoDeLaCasa, ClaveDeLaCasa>(
  (ref, clave) => ref.watch(observarContextoDeLaCasaUseCaseProvider)(
    ubicacionId: clave.ubicacionId,
    tipo: clave.tipo,
  ),
  retry: _sinReintentos,
);

/// Lo que recibe «Registrar visita» (vista 39, tabla de contratos): la ubicación y el espacio ya
/// resueltos. En un edificio [espacioId] es `null`: el depto lo elige quien recibe esto (C·09).
typedef ContextoDeVisita = ({String ubicacionId, String? espacioId});

/// Lo que recibe «$ Cobrar»: lo mismo y la persona que debe; la venta se elige después (C·08).
typedef ContextoDeCobro = ({String ubicacionId, String? espacioId, String personaId});

/// Lo que recibe «Programar entrevista» (R·02, #408) después de «¿Con quién es la entrevista?»: la
/// casa y, si se sabe, con quién. Con «Todavía no sé con quién» (o una casa sin personas)
/// [espacioPersonaId] y [personaId] son `null`: la cita queda sin persona.
typedef ContextoDeCita = ({
  String ubicacionId,
  String espacioId,
  String? espacioPersonaId,
  String? personaId,
});

/// Lo que recibe «Entrevista dada» (la entrevista en curso, #450) después de «¿Con quién?».
typedef ContextoDeEntrevista = ({
  String ubicacionId,
  String espacioId,
  PersonaDeLaEntrevista persona,
});

/// A dónde lleva «✓ Registrar visita» (#411, «¿Qué pasó?»). **Sin destino**: mientras sea `null` el
/// botón no se muestra (HU-UBI-003, «los botones llegan con la HU que los resuelve y no se muestran
/// mientras no tengan a dónde llevar»). Devuelve `true` si algo se resolvió y la hoja de la casa se
/// cierra; con cualquier otro valor la hoja sigue abierta. Cuando vuelve, el marcador ya tiene el
/// color nuevo (la lista es reactiva).
final registrarVisitaDesdeLaCasaProvider = Provider<FutureOr<Object?> Function(ContextoDeVisita)?>(
  (ref) => null,
);

/// A dónde lleva «Programar entrevista» (R·02, #408: «Elegís día y franja»). Devuelve `true` si la
/// cita se agendó. Sin destino, la opción no se ofrece en «¿Qué pasó?».
final programarEntrevistaDesdeLaCasaProvider =
    Provider<FutureOr<Object?> Function(ContextoDeCita)?>((ref) => null);

/// A dónde lleva «Entrevista dada» (#450: «Empieza a contar el tiempo»). Devuelve `true` si la
/// entrevista se dio. Sin destino, la opción no se ofrece en «¿Qué pasó?».
final entrevistaDadaDesdeLaCasaProvider =
    Provider<FutureOr<Object?> Function(ContextoDeEntrevista)?>((ref) => null);

/// A dónde lleva «$ Cobrar» (#440, «¿Qué venta?»), tanto desde la hoja de la casa como desde la opción
/// «Cobranza» de «¿Qué pasó?». Devuelve `true` si se cobró (desde «¿Qué pasó?» la visita queda
/// guardada como «Cobranza»). Sin destino, el botón y la opción no se muestran.
final cobrarDesdeLaCasaProvider = Provider<FutureOr<Object?> Function(ContextoDeCobro)?>(
  (ref) => null,
);

/// Lo que recibe «Ver la ficha» de una persona de la pestaña Personas (vista 39 C·02: «Tocar una
/// persona abre su ficha», vista 32 B): la persona y el espacio ya puestos.
typedef ContextoDeFicha = ({String personaId, String espacioId});

/// A dónde lleva tocar una persona de la pestaña Personas (la ficha de la persona, vista 32 B,
/// HU-UBI-009). **Sin destino**: mientras sea `null` la fila no se puede tocar y no lleva «›»
/// (HU-UBI-003: los botones no se muestran mientras no tengan a dónde llevar). Cuando la persona
/// vuelve, la hoja de la casa sigue abierta donde estaba.
final fichaDePersonaDesdeLaCasaProvider = Provider<FutureOr<Object?> Function(ContextoDeFicha)?>(
  (ref) => null,
);

/// Lo que recibe el contenido de una pestaña de la hoja arriba (Historial o Notas) para dibujarse: la
/// casa y el espacio ya resueltos, el colportor con la sesión iniciada y si la casa está dada de baja
/// (solo lectura).
typedef ContextoDePestana = ({
  String ubicacionId,
  String espacioId,
  String? colportorId,
  bool esBaja,
});

/// Arma el contenido de una pestaña de la hoja arriba.
typedef ConstructorDePestana = Widget Function(BuildContext context, ContextoDePestana contexto);

/// La pestaña **Historial** de la hoja arriba (C·03 y C·04, #446). **Sin contenido**: mientras sea
/// `null` la pestaña no se ofrece (llega con su issue; no se dibuja una pestaña vacía).
final pestanaHistorialDeLaCasaProvider = Provider<ConstructorDePestana?>((ref) => null);

/// La pestaña **Notas** de la hoja arriba (C·05, #447). **Sin contenido**: mientras sea `null` la
/// pestaña no se ofrece.
final pestanaNotasDeLaCasaProvider = Provider<ConstructorDePestana?>((ref) => null);
