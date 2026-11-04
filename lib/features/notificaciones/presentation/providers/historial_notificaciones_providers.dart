import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../data/datasources/consultor_destinos_notificacion_drift.dart';
import '../../data/datasources/historial_notificaciones_local_data_source_drift.dart';
import '../../data/repositories/historial_notificaciones_repository_impl.dart';
import '../../domain/entities/destino_notificacion.dart';
import '../../domain/entities/notificacion.dart';
import '../../domain/repositories/historial_notificaciones_repository.dart';
import '../../domain/usecases/historial_notificaciones_use_cases.dart';

// Cableado del historial de avisos y del centro de notificaciones (HU-NOT-005). Presentation conoce
// domain; data se inyecta acá.

/// Sin reintento automático: si no se puede leer el historial, la pantalla ofrece «Reintentar» (con
/// el reintento por defecto de Riverpod 3 el error tardaría minutos en llegar).
Duration? _sinReintentos(int intento, Object error) => null;

/// El reloj del historial (los 90 días, la hora de «leída»); un test lo reemplaza.
final relojHistorialNotificacionesProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// El historial en la DB cifrada. Sin DB abierta no hay dónde leer: lanza, y quien lo lee lo traduce
/// a un error de la pantalla.
final historialNotificacionesRepositoryProvider = Provider<HistorialNotificacionesRepository>((
  ref,
) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return HistorialNotificacionesRepositoryImpl(HistorialNotificacionesLocalDataSourceDrift(db));
});

/// Si el lugar al que lleva un aviso sigue en el teléfono.
final consultorDestinosNotificacionProvider = Provider<ConsultorDestinosNotificacion>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return ConsultorDestinosNotificacionDrift(db);
});

/// Guarda un aviso recibido. Es lo que llama quien lo recibe: el recordatorio local de una visita
/// cuando suena (HU-NOT-002) y, en el S11, las push (HU-NOT-003).
final registrarNotificacionUseCaseProvider = Provider<RegistrarNotificacionUseCase>(
  (ref) => RegistrarNotificacionUseCase(
    ref.watch(historialNotificacionesRepositoryProvider),
    ahora: ref.watch(relojHistorialNotificacionesProvider),
  ),
);

final marcarNotificacionLeidaUseCaseProvider = Provider<MarcarNotificacionLeidaUseCase>(
  (ref) => MarcarNotificacionLeidaUseCase(
    ref.watch(historialNotificacionesRepositoryProvider),
    ahora: ref.watch(relojHistorialNotificacionesProvider),
  ),
);

final marcarTodasLeidasUseCaseProvider = Provider<MarcarTodasLeidasUseCase>(
  (ref) => MarcarTodasLeidasUseCase(
    ref.watch(historialNotificacionesRepositoryProvider),
    ahora: ref.watch(relojHistorialNotificacionesProvider),
  ),
);

final borrarTodasLasNotificacionesUseCaseProvider = Provider<BorrarTodasLasNotificacionesUseCase>(
  (ref) =>
      BorrarTodasLasNotificacionesUseCase(ref.watch(historialNotificacionesRepositoryProvider)),
);

final purgarHistorialNotificacionesUseCaseProvider = Provider<PurgarHistorialNotificacionesUseCase>(
  (ref) => PurgarHistorialNotificacionesUseCase(
    ref.watch(historialNotificacionesRepositoryProvider),
    ahora: ref.watch(relojHistorialNotificacionesProvider),
  ),
);

final resolverDestinoNotificacionUseCaseProvider = Provider<ResolverDestinoNotificacionUseCase>(
  (ref) => ResolverDestinoNotificacionUseCase(ref.watch(consultorDestinosNotificacionProvider)),
);

/// Cuántos avisos siguen sin leer: el número de la campana. Sin DB abierta (o si la lectura falla)
/// queda en error y la campana lo muestra como 0: nunca asusta con un error, el motivo está en el
/// centro.
final notificacionesNoLeidasProvider = StreamProvider.autoDispose<int>((ref) {
  final repositorio = ref.watch(historialNotificacionesRepositoryProvider);
  return repositorio.observarNoLeidas(ahora: ref.watch(relojHistorialNotificacionesProvider)());
}, retry: _sinReintentos);

/// Los avisos de los últimos 90 días, el más reciente primero. Vive mientras el centro está abierto.
final historialNotificacionesProvider = StreamProvider.autoDispose<List<Notificacion>>((ref) {
  final repositorio = ref.watch(historialNotificacionesRepositoryProvider);
  return repositorio.observar(ahora: ref.watch(relojHistorialNotificacionesProvider)());
}, retry: _sinReintentos);

/// Abre el lugar al que lleva un aviso (R-NO05: el mismo enlace que la notificación original).
typedef AbridorDestinoNotificacion =
    Future<void> Function(BuildContext context, DestinoNotificacion destino);

/// Cómo se abre cada destino. **Todavía sin efecto**: tocar un aviso lo marca como leído y comprueba
/// que su destino exista (24C·07), pero el detalle de la agenda (vista 23, 23C·01) lo construye
/// HU-VIS-002/003 y esa pantalla reemplaza este proveedor en `main.dart` con su navegación.
final abridorDestinoNotificacionProvider = Provider<AbridorDestinoNotificacion>(
  (ref) => (context, destino) async {},
);
