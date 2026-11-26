import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../auth/domain/entities/campania_inscripta.dart';
import '../../../auth/presentation/providers/campanias_inscriptas_providers.dart';
import '../../data/repositories/acompaniamiento_repository_drift.dart';
import '../../data/repositories/fakes/acompaniamiento_repository_en_memoria.dart';
import '../../domain/entities/acompaniante.dart';
import '../../domain/entities/tendencia_de_la_jornada.dart';
import '../../domain/repositories/acompaniamiento_repository.dart';
import '../../domain/services/campania_de_la_jornada.dart';

/// El acompañamiento de la jornada (HU-JOR-003) y la tendencia del cierre (vista 21). Con la DB local
/// abierta lee y escribe ahí; sin ella (tests, sin sesión) queda en memoria.
final acompaniamientoRepositoryProvider = Provider<AcompaniamientoRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) return AcompaniamientoRepositoryEnMemoria();
  return AcompaniamientoRepositoryDrift(db, encolador: ref.watch(encoladorSyncProvider));
});

/// La jornada para la que se pide la lista de acompañantes: de quién es y cuándo empezó (de ahí sale su
/// campaña).
typedef ClaveDeLaLista = ({String colportorId, DateTime inicio});

/// Las campañas con inscripción viva, o `null` si no se pudieron leer: nunca rompe la lista.
Future<List<CampaniaInscripta>?> _inscripciones(Ref ref, String colportorId) async {
  try {
    return await ref.watch(campaniasInscriptasProvider(colportorId).future);
  } on Object {
    return null;
  }
}

/// Si el teléfono sabe de qué campaña es la jornada: si no, la lista ofrece los coordinadores de todas las
/// campañas de la colportora y los textos lo dicen.
final campaniaDeLaJornadaConocidaProvider = FutureProvider.autoDispose.family<bool, ClaveDeLaLista>(
  (ref, clave) async {
    final inscripciones = await _inscripciones(ref, clave.colportorId);
    return CampaniaDeLaJornada.de(inscripciones, clave.inicio) != null;
  },
);

/// Los coordinadores de la campaña de la jornada que se ofrecen en «¿Quién te acompaña?»: baja con la
/// sincronización y se usa sin conexión (decisión de Cristian, 05/11, «Lista s/red»). Si el teléfono no sabe
/// cuál es la campaña de la jornada, los de todas en las que la colportora está inscripta.
final listaDeAcompanantesProvider = StreamProvider.autoDispose
    .family<List<CoordinadorDeCampania>, ClaveDeLaLista>((ref, clave) async* {
      final repositorio = ref.watch(acompaniamientoRepositoryProvider);
      final inscripciones = await _inscripciones(ref, clave.colportorId);
      // La hoja se pudo cerrar mientras se leían las inscripciones: ya nadie escucha.
      if (!ref.mounted) return;
      final campania = CampaniaDeLaJornada.de(inscripciones, clave.inicio);
      yield* repositorio.observarLista(
        colportorId: clave.colportorId,
        campaniaIds: campania == null ? null : {campania.campaniaId},
      );
    });

/// Quienes acompañan la jornada [jornadaId] hoy.
final acompaniantesDeLaJornadaProvider = StreamProvider.autoDispose
    .family<List<Acompaniante>, String>(
      (ref, jornadaId) => ref.watch(acompaniamientoRepositoryProvider).observarDe(jornadaId),
    );

/// La jornada de la que se pide la tendencia: [fin] en `null` es una en curso.
typedef ClaveDeLaTendencia = ({
  String colportorId,
  String jornadaId,
  DateTime inicio,
  DateTime? fin,
});

/// Cómo va la jornada contra la última cerrada de la misma campaña; `null` mientras no se sabe cuál es su
/// campaña (no se afirma una «primera jornada» que no se sabe).
final tendenciaDeLaJornadaProvider = StreamProvider.autoDispose
    .family<TendenciaDeLaJornada?, ClaveDeLaTendencia>((ref, clave) async* {
      final repositorio = ref.watch(acompaniamientoRepositoryProvider);
      final inscripciones = await _inscripciones(ref, clave.colportorId);
      if (!ref.mounted) return;
      final campania = CampaniaDeLaJornada.de(inscripciones, clave.inicio);
      yield* repositorio.observarTendencia(
        colportorId: clave.colportorId,
        jornadaId: clave.jornadaId,
        inicio: clave.inicio,
        fin: clave.fin,
        campania: campania == null ? null : (desde: campania.fechaInicio, hasta: campania.fechaFin),
      );
    });
