import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/fuentes_sin_adaptador_ubicaciones.dart';
import '../../domain/services/consultor_pendientes_ubicacion.dart';
import '../../domain/usecases/baja_ubicacion_use_cases.dart';
import 'alta_ubicacion_providers.dart';

// Cableado de la baja y la reactivación de una ubicación (HU-UBI-005, vista 09). Comparte con el alta
// el repositorio y el reloj.

/// Lo que la ubicación tiene y la baja toca o impide. Visitas, ventas y cobranzas todavía no existen en
/// el teléfono: hasta entonces [PendientesUbicacionSinFuente], que devuelve la falla de revisión (no
/// «no hay nada»); el adaptador real es front-colportores-mobile#330.
final consultorPendientesUbicacionProvider = Provider<ConsultorPendientesUbicacion>(
  (ref) => PendientesUbicacionSinFuente(),
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
  ),
);

/// «Reactivar» desde la Lista con el filtro «Con bajas» (y su «Deshacer» es una baja más).
final reactivarUbicacionUseCaseProvider = Provider<ReactivarUbicacionUseCase>(
  (ref) => ReactivarUbicacionUseCase(
    ref.watch(ubicacionRepositoryProvider),
    ahora: ref.watch(relojAltaUbicacionProvider),
  ),
);
