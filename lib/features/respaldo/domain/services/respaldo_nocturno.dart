import '../../../../core/logging/app_logger.dart';
import 'servicio_respaldo.dart';

/// Cómo terminó la corrida de la noche, para el sistema que la despertó.
enum DesenlaceNocturno {
  /// No hay nada más que hacer hoy: se respaldó, o no correspondía (sin sesión, sin Drive) o hace
  /// falta que la persona haga algo (reconectar Drive, liberar espacio). La próxima ventana lo
  /// vuelve a mirar.
  terminado,

  /// Se pudo y no salió (sin red, sin Wi-Fi, falló la subida): que el sistema vuelva a intentarlo
  /// más tarde, con su espera creciente, sin esperar a la noche siguiente.
  reintentar,
}

/// La sesión de trabajo de una corrida nocturna: el respaldo ya armado sobre la DB abierta.
abstract interface class SesionDeRespaldoNocturno {
  ServicioRespaldo get servicio;

  /// Cuándo fue la última verificación de la cadena, o `null` si nunca se hizo.
  Future<DateTime?> ultimaVerificacion();

  /// Cierra la DB y suelta lo que se armó. Se llama siempre, haya salido bien o mal.
  Future<void> cerrar();
}

/// El respaldo de la noche (HU-SYNC-005, #583): lo que corre el sistema a las 03:00, con la app
/// cerrada y sin pantalla. Abre la sesión de respaldo, pide el respaldo automático, hace la
/// verificación semanal de la cadena si toca (HU-SYNC-009) y cierra la DB.
///
/// **Nada lanza**: cualquier falla vuelve como [DesenlaceNocturno.reintentar]. Lo que se anota en los
/// logs es el estado, nunca cuentas ni contenido.
final class RespaldoNocturno {
  RespaldoNocturno({
    required this.abrir,
    DateTime Function()? ahora,
    this.cadaCuantoVerificar = const Duration(days: 7),
    AppLogger? logger,
  }) : _ahora = ahora ?? (() => DateTime.now().toUtc()),
       _log = logger ?? AppLogger.instance;

  /// Arma la sesión de trabajo, o devuelve `null` si hoy no hay nada para respaldar (sin sesión
  /// guardada, sin Drive conectado, sin DB o sin llave). Puede lanzar: se cuenta como falla y se
  /// reintenta (por ejemplo, el almacén seguro que no deja leer la sesión, #691).
  final Future<SesionDeRespaldoNocturno?> Function() abrir;

  final DateTime Function() _ahora;
  final Duration cadaCuantoVerificar;
  final AppLogger _log;

  Future<DesenlaceNocturno> ejecutar() async {
    SesionDeRespaldoNocturno? sesion;
    try {
      sesion = await abrir();
      if (sesion == null) {
        _log.info(LogModulo.backup, 'BACKUP_NOCTURNO', 'nada para respaldar esta noche');
        return DesenlaceNocturno.terminado;
      }
      final resultado = await sesion.servicio.respaldar(OrigenRespaldo.nocturno);
      final desenlace = desenlaceDe(resultado);
      // La verificación semanal también va de noche, con Wi-Fi: baja la cadena entera. Si el
      // respaldo no pudo (sin Wi-Fi, sin Drive), tampoco la verificación: usa las mismas condiciones.
      if (resultado is RespaldoHecho && await _tocaVerificar(sesion)) {
        await sesion.servicio.verificarIntegridad();
      }
      _log.info(LogModulo.backup, 'BACKUP_NOCTURNO', 'corrida de la noche terminada', {
        'desenlace': desenlace.name,
      });
      return desenlace;
    } on Object catch (e) {
      _log.warn(LogModulo.backup, 'BACKUP_NOCTURNO_FALLO', 'la corrida de la noche falló', {
        'error': e.runtimeType.toString(),
      });
      return DesenlaceNocturno.reintentar;
    } finally {
      await _cerrar(sesion);
    }
  }

  /// Qué hace el sistema con cada resultado del respaldo.
  static DesenlaceNocturno desenlaceDe(ResultadoRespaldo resultado) => switch (resultado) {
    RespaldoHecho() => DesenlaceNocturno.terminado,
    // Sin Drive o sin motor no hay nada que reintentar; en curso y fallo reciente ya hay otro
    // intento en marcha o recién hecho.
    RespaldoOmitido(motivo: MotivoOmision.sinDrive) ||
    RespaldoOmitido(motivo: MotivoOmision.sinMotor) ||
    RespaldoOmitido(motivo: MotivoOmision.enCurso) ||
    RespaldoOmitido(motivo: MotivoOmision.falloReciente) => DesenlaceNocturno.terminado,
    RespaldoOmitido() => DesenlaceNocturno.reintentar,
    // El permiso o el espacio los arregla la persona: reintentar de noche no sirve.
    RespaldoFallido(causa: CausaFalloRespaldo.permiso) ||
    RespaldoFallido(causa: CausaFalloRespaldo.sinEspacio) => DesenlaceNocturno.terminado,
    RespaldoFallido() => DesenlaceNocturno.reintentar,
  };

  Future<bool> _tocaVerificar(SesionDeRespaldoNocturno sesion) async {
    final ultima = await sesion.ultimaVerificacion();
    return ultima == null || _ahora().difference(ultima) >= cadaCuantoVerificar;
  }

  Future<void> _cerrar(SesionDeRespaldoNocturno? sesion) async {
    if (sesion == null) return;
    try {
      await sesion.cerrar();
    } on Object catch (e) {
      _log.warn(LogModulo.backup, 'BACKUP_NOCTURNO_CIERRE', 'no se pudo cerrar la sesión', {
        'error': e.runtimeType.toString(),
      });
    }
  }
}
