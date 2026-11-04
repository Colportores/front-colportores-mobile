import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../data/repositories/entrevistas_cercanas_repository_drift.dart';
import '../../domain/entities/entrevista_cercana.dart';
import '../../domain/repositories/entrevistas_cercanas_repository.dart';
import 'agenda_providers.dart';

// Cableado de la fecha sugerida de «Agendar visita» (vista 39, R·02).

/// Lee del teléfono las entrevistas agendadas cerca de una casa. Sin DB abierta no hay de dónde leer:
/// lanza, y la pantalla lo toma como «sin sugerencia» (la ayuda es opcional: nunca frena el agendado).
final entrevistasCercanasRepositoryProvider = Provider<EntrevistasCercanasRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return EntrevistasCercanasRepositoryDrift(db);
});

/// Riverpod 3 reintenta 10 veces lo que falla: acá una falla es «sin sugerencia», enseguida.
Duration? _sinReintentos(int intento, Object error) => null;

/// De qué casa y de quién se piden las entrevistas cercanas.
typedef ClaveEntrevistasCercanas = ({String espacioId, String colportorId});

/// El logger de la lectura de las entrevistas cercanas; un test lo reemplaza para leer lo que escribe.
final entrevistasCercanasLoggerProvider = Provider<AppLogger>((ref) => AppLogger.instance);

/// Las entrevistas que [ClaveEntrevistasCercanas.colportorId] tiene agendadas, desde ahora, a menos de
/// 300 m de la casa del espacio. Se lee una vez al abrir la pantalla.
///
/// Si la lectura falla, la pantalla no muestra nada (la sugerencia es una ayuda), pero la falla no se
/// traga: queda un `warn` con el tipo del error y sin datos de la persona ni de la casa (convenciones
/// §7.5), y se relanza para que el provider quede en error.
final entrevistasCercanasProvider = FutureProvider.autoDispose
    .family<List<EntrevistaCercana>, ClaveEntrevistasCercanas>((ref, clave) async {
      final logger = ref.read(entrevistasCercanasLoggerProvider);
      try {
        final ahora = ref.read(relojVisitaProvider)();
        return await ref
            .watch(entrevistasCercanasRepositoryProvider)
            .leer(
              colportorId: clave.colportorId,
              espacioId: clave.espacioId,
              desde: DateTime(ahora.year, ahora.month, ahora.day, ahora.hour, ahora.minute),
            );
      } on Object catch (e) {
        logger.warn(
          LogModulo.agenda,
          'ENTREVISTAS_CERCANAS',
          'no se pudieron leer las entrevistas cercanas: no se sugiere fecha',
          {'error': e.runtimeType.toString()},
        );
        rethrow;
      }
    }, retry: _sinReintentos);
