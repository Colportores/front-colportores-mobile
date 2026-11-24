import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../agenda/presentation/providers/recordatorios_providers.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';
import '../../../cobranzas/data/datasources/cuotas_local_data_source_drift.dart';
import '../../data/services/fuentes_sin_adaptador_ubicaciones.dart';
import '../../data/services/pendientes_ubicacion_drift.dart';
import '../../domain/entities/pendientes_ubicacion.dart';
import '../../domain/services/consultor_pendientes_ubicacion.dart';
import '../../domain/usecases/baja_ubicacion_use_cases.dart';
import 'alta_ubicacion_providers.dart';
import 'house_status_providers.dart';

// Cableado de la baja y la reactivación de una ubicación (HU-UBI-005, vista 09). Comparte con el alta
// el repositorio y el reloj.

/// Lo que la ubicación tiene y la baja toca o impide, leído de la DB local (ventas, cobranzas, visitas y
/// entrevistas agendadas: [PendientesUbicacionDrift], #330). Sin DB abierta o sin sesión no hay de dónde
/// leer: [PendientesUbicacionSinFuente], que devuelve la falla de revisión (no «no hay nada»).
final consultorPendientesUbicacionProvider = Provider<ConsultorPendientesUbicacion>((ref) {
  final db = ref.watch(dbLocalProvider);
  final colportorId = ref.watch(sesionProvider).value?.usuarioId.trim() ?? '';
  if (db == null || colportorId.isEmpty) return PendientesUbicacionSinFuente();
  return PendientesUbicacionDrift(
    db,
    cuotas: CuotasLocalDataSourceDrift(
      db,
      encolador: ref.watch(encoladorSyncProvider),
      estadoDeLasCasas: ref.watch(houseStatusUpdaterProvider),
    ),
    colportorId: colportorId,
  );
});

/// A dónde lleva «Ir a la cobranza» de la baja bloqueada por una cobranza (vista 09·02): abre el cobro de
/// la venta que se debe. Lo enchufa `main.dart`; sin destino (`null`) la hoja no dibuja el botón y deja
/// solo el aviso y «Entendido» (HU-UBI-005: «solo si el destino existe»). Devuelve `true` si se cobró.
final irALaCobranzaDesdeLaBajaProvider = Provider<FutureOr<Object?> Function(CobranzaPendiente)?>(
  (ref) => null,
);

/// Lo que se mira antes de ofrecer la baja: si está bloqueada y si pide una segunda confirmación.
final consultarPendientesBajaUseCaseProvider = Provider<ConsultarPendientesBajaUseCase>(
  (ref) => ConsultarPendientesBajaUseCase(ref.watch(consultorPendientesUbicacionProvider)),
);

/// La baja (HU-UBI-005): control de edición concurrente, bloqueos, segunda confirmación y escritura
/// con el sync encolado y el motivo en la auditoría local.
final darDeBajaUbicacionUseCaseProvider = Provider<DarDeBajaUbicacionUseCase>(
  (ref) => DarDeBajaUbicacionUseCase(
    ref.watch(ubicacionRepositoryProvider),
    ref.watch(consultorPendientesUbicacionProvider),
    ahora: ref.watch(relojAltaUbicacionProvider),
    recordatorios: ref.watch(recordatoriosProvider),
  ),
);

/// «Reactivar» desde la Lista con el filtro «Con bajas» (y su «Deshacer» es una baja más).
final reactivarUbicacionUseCaseProvider = Provider<ReactivarUbicacionUseCase>(
  (ref) => ReactivarUbicacionUseCase(
    ref.watch(ubicacionRepositoryProvider),
    ahora: ref.watch(relojAltaUbicacionProvider),
  ),
);
