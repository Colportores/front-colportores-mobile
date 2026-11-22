import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/database_providers.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../respaldo/presentation/providers/respaldo_automatico_providers.dart';
import '../../data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import '../../data/datasources/jornada_local_data_source.dart';
import '../../data/datasources/jornada_local_data_source_drift.dart';
import '../../data/repositories/jornada_repository_impl.dart';
import '../../data/repositories/jornadas_abiertas_repository_impl.dart';
import '../../data/services/disparador_backup_respaldo.dart';
import '../../domain/repositories/jornada_repository.dart';
import '../../domain/repositories/jornadas_abiertas_repository.dart';
import '../../domain/services/disparador_backup.dart';
import '../../domain/usecases/finalizar_jornada_anterior_use_case.dart';
import '../../domain/usecases/finalizar_jornada_use_case.dart';
import '../../domain/usecases/iniciar_jornada_use_case.dart';
import '../../domain/usecases/jornadas_por_cerrar_use_case.dart';
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
  if (db != null) {
    return JornadaLocalDataSourceDrift(db, encolador: ref.watch(encoladorSyncProvider));
  }

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

/// El backup automático que se pide al cerrar la jornada (HU-JOR-002 → HU-SYNC-005): lo hace el
/// respaldo en Drive si hay Wi-Fi y batería ≥ 30 %, y si no, queda para la próxima vuelta a la app.
@Riverpod(keepAlive: true)
DisparadorBackup disparadorBackup(Ref ref) =>
    DisparadorBackupRespaldo(ref.watch(servicioRespaldoProvider));

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

/// Todas las jornadas abiertas del colportor (HU-JOR-002, «Jornada que quedó abierta»): lo que sale de
/// una recuperación de dispositivo con dos abiertas.
@Riverpod(keepAlive: true)
JornadasAbiertasRepository jornadasAbiertasRepository(Ref ref) =>
    JornadasAbiertasRepositoryImpl(ref.watch(jornadaLocalDataSourceProvider));

/// Las jornadas abiertas que tienen otra después, para preguntar a qué hora terminó cada una.
@Riverpod(keepAlive: true)
JornadasPorCerrarUseCase jornadasPorCerrarUseCase(Ref ref) => JornadasPorCerrarUseCase(
  ref.watch(jornadasAbiertasRepositoryProvider),
  ref.watch(jornadaRepositoryProvider),
);

/// Cierra una jornada abierta que tiene otra después, con la hora que eligió la persona.
@Riverpod(keepAlive: true)
FinalizarJornadaAnteriorUseCase finalizarJornadaAnteriorUseCase(Ref ref) =>
    FinalizarJornadaAnteriorUseCase(
      ref.watch(jornadasAbiertasRepositoryProvider),
      ref.watch(jornadaRepositoryProvider),
      ref.watch(disparadorBackupProvider),
      ahora: ref.watch(relojJornadaProvider),
      alFallarBackup: (error, rastro) => AppLogger.instance.error(
        LogModulo.backup,
        'BACKUP_PEDIDO_FAIL',
        'no se pudo pedir el backup al cerrar la jornada',
        const {},
        error,
        rastro,
      ),
    );
