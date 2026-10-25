import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../data/datasources/nota_del_lugar_local_data_source_drift.dart';
import '../../domain/entities/contexto_de_la_casa.dart';
import '../../domain/entities/ubicacion.dart';
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

final observarContextoDeLaCasaUseCaseProvider = Provider<ObservarContextoDeLaCasaUseCase>(
  (ref) => ObservarContextoDeLaCasaUseCase(
    espacios: ref.watch(espacioRepositoryProvider),
    personas: ref.watch(personaRepositoryProvider),
    saldos: ref.watch(saldosDePersonasProvider),
    notas: ref.watch(lectorNotasDelLugarProvider),
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

/// A dónde lleva «✓ Registrar visita» (#411, «¿Qué pasó?»). **Sin destino todavía**: mientras sea
/// `null` el botón no se muestra (HU-UBI-003, «los botones llegan con la HU que los resuelve y no se
/// muestran mientras no tengan a dónde llevar»). Cuando vuelve la hoja sigue abierta, y el marcador
/// ya tiene el color nuevo (la lista es reactiva).
final registrarVisitaDesdeLaCasaProvider = Provider<FutureOr<void> Function(ContextoDeVisita)?>(
  (ref) => null,
);

/// A dónde lleva «$ Cobrar» (#440, «¿Qué venta?»). Sin destino, el botón no se muestra.
final cobrarDesdeLaCasaProvider = Provider<FutureOr<void> Function(ContextoDeCobro)?>(
  (ref) => null,
);
