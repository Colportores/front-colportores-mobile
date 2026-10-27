import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../mapa/presentation/providers/ubicacion_alternativa_providers.dart';
import '../../data/repositories/cobranzas_en_otra_ubicacion_repository_drift.dart';
import '../../domain/entities/destino_de_cobranza.dart';
import '../../domain/repositories/cobranzas_en_otra_ubicacion_repository.dart';
import '../../domain/usecases/observar_destino_de_cobranza_use_case.dart';

// Cableado de HU-VIS-006 (agendar una cobranza en la ubicación alternativa), sin pantalla: la vista 22
// que la dibuja no está en `disenio-vistas/` (docs/vistas-por-sprint.md: «Sin artboard / falta»).

/// Riverpod 3 reintenta 10 veces lo que falla: la pantalla muestra el error enseguida y el
/// «Reintentar» es de quien lo toca.
Duration? _sinReintentos(int intento, Object error) => null;

/// Dónde proponer la cobranza de una persona: la alternativa activa, la del espacio, o la advertencia
/// de que la alternativa ya no sirve. Se actualiza sola cuando cambia la alternativa.
final destinoDeCobranzaProvider = StreamProvider.autoDispose
    .family<DestinoDeCobranza, ClaveAlternativa>(
      (ref, clave) => ObservarDestinoDeCobranzaUseCase(
        ref.watch(ubicacionAlternativaRepositoryProvider),
      )(personaId: clave.personaId, espacioId: clave.espacioId),
      retry: _sinReintentos,
    );

/// Lee de la DB cifrada qué ubicaciones tienen una cobranza que viene de otra. Sin DB abierta lanza.
final cobranzasEnOtraUbicacionRepositoryProvider = Provider<CobranzasEnOtraUbicacionRepository>((
  ref,
) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return CobranzasEnOtraUbicacionRepositoryDrift(db);
});

/// Los ids de las ubicaciones cuyo marcador lleva el indicador «cobranza pendiente proveniente de
/// otra ubicación» (HU-VIS-006). El marcador todavía no lo dibuja: falta el diseño.
final ubicacionesConCobranzaDeOtraProvider = StreamProvider.autoDispose.family<Set<String>, String>(
  (ref, colportorId) => ref
      .watch(cobranzasEnOtraUbicacionRepositoryProvider)
      .observarUbicaciones(colportorId: colportorId),
  retry: _sinReintentos,
);
