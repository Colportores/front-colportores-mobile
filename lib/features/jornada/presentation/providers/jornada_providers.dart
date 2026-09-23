import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import '../../data/datasources/jornada_local_data_source.dart';
import '../../data/datasources/jornada_local_data_source_drift.dart';
import '../../data/repositories/jornada_repository_impl.dart';
import '../../domain/repositories/jornada_repository.dart';
import '../../domain/usecases/iniciar_jornada_use_case.dart';
import '../../domain/usecases/obtener_jornada_activa_use_case.dart';

part 'jornada_providers.g.dart';

// Cableado de la feature (ADR-009): presentation conoce domain; data se inyecta acá.

/// Reloj de la feature. Los tests lo sobreescriben para fijar la hora sin esperar.
@Riverpod(keepAlive: true)
DateTime Function() relojJornada(Ref ref) => DateTime.now;

/// La tabla `jornada` de la DB local cifrada si la DB está abierta (`dbLocalProvider`).
///
/// TODO(#27): hoy nadie abre la DB — el login todavía no deriva la clave (HU-AUTH-009) —, así
/// que mientras tanto la jornada vive en memoria, igual que la sesión (`main.dart` usa
/// `AuthLocalDataSourceEnMemoria`): la pantalla funciona, pero la jornada **se pierde al cerrar
/// la app**. Cuando el login abra la DB, este provider se reconstruye solo (observa
/// `dbLocalProvider`) y pasa a Drift sin tocar nada más.
@Riverpod(keepAlive: true)
JornadaLocalDataSource jornadaLocalDataSource(Ref ref) {
  final db = ref.watch(dbLocalProvider);
  if (db != null) return JornadaLocalDataSourceDrift(db);

  AppLogger.instance.warn(
    LogModulo.db,
    'JORNADA_SIN_DB',
    'la DB local no está abierta: la jornada se guarda en memoria',
  );
  return JornadaLocalDataSourceEnMemoria();
}

@Riverpod(keepAlive: true)
JornadaRepository jornadaRepository(Ref ref) =>
    JornadaRepositoryImpl(ref.watch(jornadaLocalDataSourceProvider));

@Riverpod(keepAlive: true)
IniciarJornadaUseCase iniciarJornadaUseCase(Ref ref) => IniciarJornadaUseCase(
  ref.watch(jornadaRepositoryProvider),
  generarId: const Uuid().v7,
  ahora: ref.watch(relojJornadaProvider),
);

@Riverpod(keepAlive: true)
ObtenerJornadaActivaUseCase obtenerJornadaActivaUseCase(Ref ref) =>
    ObtenerJornadaActivaUseCase(ref.watch(jornadaRepositoryProvider));
