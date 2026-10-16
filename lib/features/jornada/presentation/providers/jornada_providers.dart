import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import '../../data/datasources/jornada_local_data_source.dart';
import '../../data/datasources/jornada_local_data_source_drift.dart';
import '../../data/repositories/jornada_repository_impl.dart';
import '../../data/services/disparador_backup_pendiente.dart';
import '../../domain/repositories/jornada_repository.dart';
import '../../domain/services/disparador_backup.dart';
import '../../domain/usecases/finalizar_jornada_use_case.dart';
import '../../domain/usecases/iniciar_jornada_use_case.dart';
import '../../domain/usecases/obtener_jornada_activa_use_case.dart';

part 'jornada_providers.g.dart';

// Cableado de la feature (ADR-009): presentation conoce domain; data se inyecta acá.

/// Reloj de la feature. Los tests lo sobreescriben para fijar la hora sin esperar.
@Riverpod(keepAlive: true)
DateTime Function() relojJornada(Ref ref) => DateTime.now;

/// La tabla `jornada` de la DB local cifrada si la DB está abierta (`dbLocalProvider`).
///
/// En la app la DB siempre está abierta cuando se llega a la jornada: la raíz no muestra la
/// pantalla principal hasta que la preparación de HU-AUTH-009 la abre (#27). La versión en memoria
/// queda para los tests de widgets que no cablean la DB, y avisa en el log si alguna vez se usa
/// fuera de ellos (la jornada **se perdería al cerrar la app**). Observa `dbLocalProvider`: al
/// abrirse o cerrarse la DB, se reconstruye solo.
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

/// El backup automático que se pide al cerrar la jornada (HU-SYNC-005). Hasta que exista, solo
/// registra el pedido ([DisparadorBackupPendiente], TODO(#74)).
@Riverpod(keepAlive: true)
DisparadorBackup disparadorBackup(Ref ref) => DisparadorBackupPendiente();

@Riverpod(keepAlive: true)
FinalizarJornadaUseCase finalizarJornadaUseCase(Ref ref) => FinalizarJornadaUseCase(
  ref.watch(jornadaRepositoryProvider),
  ref.watch(disparadorBackupProvider),
  ahora: ref.watch(relojJornadaProvider),
  // El colportor no puede hacer nada con esto (el cierre ya quedó guardado): solo va al log.
  alFallarBackup: (error, rastro) => AppLogger.instance.error(
    LogModulo.backup,
    'BACKUP_PEDIDO_FAIL',
    'no se pudo pedir el backup al cerrar la jornada',
    const {},
    error,
    rastro,
  ),
);
