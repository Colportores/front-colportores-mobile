import '../../../../core/logging/app_logger.dart';
import '../../domain/services/programador_respaldo_nocturno.dart';
import '../../domain/services/ventana_nocturna.dart';

/// Lo que el respaldo de la noche le pide al planificador de tareas del sistema. Es la costura con
/// el plugin (`workmanager`, ver `TareasWorkmanager`): acá no hay nada de plataforma, así que el
/// resto se prueba en la VM.
abstract interface class TareasDelSistema {
  /// Una tarea que el sistema repite cada [cada], la primera vez pasada [primeraEspera]. Con
  /// [soloWifi] pide una red sin tarifa por consumo; con [cargando], el teléfono enchufado.
  /// Reemplaza la que tuviera el mismo [nombre].
  Future<void> periodica({
    required String nombre,
    required Duration cada,
    required Duration primeraEspera,
    required bool soloWifi,
    required bool cargando,
  });

  /// Una tarea que el sistema corre una sola vez, no antes de [espera]. Es lo que hay en iOS, donde
  /// el sistema no repite las tareas de procesamiento: cada corrida programa la siguiente.
  Future<void> unaVez({
    required String nombre,
    required Duration espera,
    required bool conRed,
    required bool cargando,
  });

  Future<void> cancelar(String nombre);
}

/// El nombre de la tarea nocturna ante el sistema. En iOS es también el identificador de
/// `BGTaskScheduler`: tiene que ser el mismo de `AppDelegate.swift` y de
/// `BGTaskSchedulerPermittedIdentifiers` en `Info.plist`.
const nombreTareaRespaldoNocturno = 'com.colportores.respaldo_nocturno';

/// [ProgramadorDeRespaldoNocturno] sobre las tareas del sistema (HU-SYNC-005, ADR-009, R30).
///
/// - **Android** (`WorkManager`): una tarea periódica de 24 horas, la primera a las 03:00, con red
///   sin tarifa por consumo y el teléfono cargando. Si el sistema la corre y falla, la repite con su
///   espera creciente.
/// - **iOS** (`BGProcessingTask`): una tarea de procesamiento por vez, con red y energía externa,
///   para la próxima 03:00. iOS no garantiza que corra (R30): lo cubre el respaldo del cierre de
///   jornada y el de la vuelta a la app con más de 24 horas sin uno. Cada corrida deja programada la
///   siguiente, y la app también al abrirse.
///
/// No lanza: lo que falla se anota (sin datos) y se sigue.
final class ProgramadorNocturnoDelSistema implements ProgramadorDeRespaldoNocturno {
  ProgramadorNocturnoDelSistema(
    this._tareas, {
    required this.esIos,
    DateTime Function()? ahora,
    AppLogger? logger,
  }) : _ahora = ahora ?? DateTime.now,
       _log = logger ?? AppLogger.instance;

  final TareasDelSistema _tareas;

  /// Si es iOS. Las demás plataformas con tareas del sistema se tratan como Android.
  final bool esIos;
  final DateTime Function() _ahora;
  final AppLogger _log;

  @override
  Future<void> programar() async {
    final espera = esperaHastaLaVentanaNocturna(_ahora());
    try {
      if (esIos) {
        await _tareas.unaVez(
          nombre: nombreTareaRespaldoNocturno,
          espera: espera,
          conRed: true,
          cargando: true,
        );
      } else {
        await _tareas.periodica(
          nombre: nombreTareaRespaldoNocturno,
          cada: const Duration(hours: 24),
          primeraEspera: espera,
          soloWifi: true,
          cargando: true,
        );
      }
    } on Object catch (e) {
      _anotar('BACKUP_NOCTURNO_PROGRAMAR', 'no se pudo programar el respaldo de la noche', e);
    }
  }

  @override
  Future<void> cancelar() async {
    try {
      await _tareas.cancelar(nombreTareaRespaldoNocturno);
    } on Object catch (e) {
      _anotar('BACKUP_NOCTURNO_CANCELAR', 'no se pudo sacar el respaldo de la noche', e);
    }
  }

  void _anotar(String operacion, String mensaje, Object error) {
    _log.warn(LogModulo.backup, operacion, mensaje, {'error': error.runtimeType.toString()});
  }
}
