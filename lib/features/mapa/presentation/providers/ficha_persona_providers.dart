import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/dispositivo/marcador_de_telefono_canal.dart';
import '../../data/datasources/ficha_persona_local_data_source_drift.dart';
import '../../data/repositories/ficha_persona_repository_impl.dart';
import '../../domain/entities/ficha_de_persona.dart';
import '../../domain/repositories/ficha_persona_repository.dart';
import '../../domain/services/marcador_de_telefono.dart';
import '../../domain/services/movimientos_de_cuenta_de_persona.dart';
import '../../domain/usecases/ficha_persona_use_cases.dart';
import 'baja_persona_providers.dart';
import 'notas_persona_providers.dart';
import 'personas_providers.dart';

// Cableado de la ficha de una persona (HU-UBI-009, vista 32B). Presentation conoce domain; data se
// inyecta acá. Todo es local: nada de la ficha sale del teléfono.

/// Riverpod 3 reintenta 10 veces lo que falla: la ficha muestra el error enseguida (32B·07) y el
/// «Reintentar» es de quien lo toca.
Duration? _sinReintentos(int intento, Object error) => null;

/// Sin DB abierta no hay dónde leer: lanza, y la ficha lo muestra como «No pudimos leer los datos de …
/// en tu teléfono.».
final fichaPersonaRepositoryProvider = Provider<FichaPersonaRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return FichaPersonaRepositoryImpl(FichaPersonaLocalDataSourceDrift(db));
});

/// De dónde salen las entregas y los cobros del historial. **Sin adaptador todavía**: llegan con las
/// tablas locales de HU-VEN-002/003 y HU-COB-001 ([MovimientosDeCuentaSinFuente]); un test o esas HU lo
/// reemplazan.
final movimientosDeCuentaProvider = Provider<MovimientosDeCuentaDeLaPersona>(
  (ref) => const MovimientosDeCuentaSinFuente(),
);

/// El marcador del teléfono. Sin estado: los tests lo reemplazan con un fake.
final marcadorDeTelefonoProvider = Provider<MarcadorDeTelefono>((ref) => MarcadorDeTelefonoCanal());

final observarFichaDePersonaUseCaseProvider = Provider<ObservarFichaDePersonaUseCase>(
  (ref) => ObservarFichaDePersonaUseCase(
    fichas: ref.watch(fichaPersonaRepositoryProvider),
    notas: ref.watch(notaPersonaRepositoryProvider),
    espacios: ref.watch(espacioRepositoryProvider),
    cuentas: ref.watch(cuentasDePersonasProvider),
    movimientos: ref.watch(movimientosDeCuentaProvider),
  ),
);

final llamarAPersonaUseCaseProvider = Provider<LlamarAPersonaUseCase>(
  (ref) => LlamarAPersonaUseCase(
    ref.watch(fichaPersonaRepositoryProvider),
    ref.watch(marcadorDeTelefonoProvider),
    ahora: ref.watch(relojPersonaProvider),
  ),
);

/// Qué ficha se lee: la persona y el espacio desde el que se abrió (en un edificio, el depto).
typedef ClaveDeFicha = ({String personaId, String espacioId});

/// La ficha de [clave], al día cuando cambia algo; `null` si la persona ya no está en el teléfono. Una
/// falla de lectura es el error del provider.
final fichaDePersonaProvider = StreamProvider.autoDispose.family<FichaDePersona?, ClaveDeFicha>(
  (ref, clave) => ref.watch(observarFichaDePersonaUseCaseProvider)(
    personaId: clave.personaId,
    espacioId: clave.espacioId,
  ),
  retry: _sinReintentos,
);

/// A dónde lleva «Editar persona» del menú «⋯» (y «Agregar» cuando no tiene teléfono): recibe el `id` de
/// la persona y devuelve cuando la edición terminó. **Sin destino** (la edición de personas, HU-UBI-010,
/// todavía no está en esta rama): mientras sea `null` esas opciones no se muestran.
final editarPersonaDesdeLaFichaProvider = Provider<FutureOr<Object?> Function(String personaId)?>(
  (ref) => null,
);
