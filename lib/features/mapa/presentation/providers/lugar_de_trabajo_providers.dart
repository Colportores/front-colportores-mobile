import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../auth/presentation/providers/sesion_notifier.dart';
import '../../../tiles/domain/services/fuente_lugar_de_trabajo.dart';
import '../../data/datasources/campanias_del_colportor_local_data_source.dart';
import '../../data/datasources/lugar_de_trabajo_local_data_source.dart';
import '../../data/services/fuente_lugar_de_trabajo_local.dart';
import 'alta_ubicacion_providers.dart' show ciudadesParaAltaProvider, relojAltaUbicacionProvider;

/// Dónde trabaja la colportora con la sesión iniciada, leído de las réplicas locales (sin red): su
/// zona, su ciudad y el departamento de esa ciudad (HU-SYNC-010, #619). La ciudad sale de
/// [ciudadesParaAltaProvider], el mismo resolvedor del mapa de la vista 06 y de «Nueva ubicación».
///
/// `main.dart` lo conecta a `fuenteLugarDeTrabajoProvider` de «Mapas offline». Sin sesión o sin la
/// base abierta contesta «no sé» ([FuenteLugarDeTrabajoLocal.sinFuente]); se reconstruye solo cuando
/// cambia la sesión o se abre la base.
final fuenteLugarDeTrabajoLocalProvider = Provider<FuenteLugarDeTrabajo>((ref) {
  final db = ref.watch(dbLocalProvider);
  final colportorId = ref.watch(sesionProvider).value?.usuarioId;
  if (db == null || colportorId == null) return FuenteLugarDeTrabajoLocal.sinFuente();
  return FuenteLugarDeTrabajoLocal(
    colportorId: colportorId,
    ciudades: ref.watch(ciudadesParaAltaProvider),
    campanias: CampaniasDelColportorLocalDataSourceDrift(db),
    lugares: LugarDeTrabajoLocalDataSourceDrift(db),
    ahora: ref.watch(relojAltaUbicacionProvider),
  );
});
