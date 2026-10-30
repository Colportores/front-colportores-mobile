/// Quién pidió el respaldo. Decide qué condiciones se exigen (HU-SYNC-005, R-SY10).
enum OrigenRespaldo {
  /// Al cerrar la jornada (HU-JOR-002). Automático: Wi-Fi y batería ≥ 30 %.
  cierreDeJornada,

  /// Al abrir la app o volver a ella con más de 24 horas sin respaldo (el fallback de iOS, R30).
  /// Automático: Wi-Fi y batería ≥ 30 %.
  alAbrir,

  /// Tras una verificación que encontró la cadena rota: se arma una base nueva (HU-SYNC-009).
  /// Automático.
  regeneracion,

  /// La persona lo pidió (el «Reintentar» del aviso) o acaba de conectar Drive. Basta con tener
  /// conexión: fue una acción suya, y el motivo de pedirlo puede ser justamente que lleva días sin
  /// respaldar.
  pedidoPorLaPersona;

  /// Si pide Wi-Fi y batería.
  bool get esAutomatico => this != pedidoPorLaPersona;
}

/// Por qué no se hizo un respaldo que no falló.
enum MotivoOmision {
  /// No hay un Drive conectado con el permiso vigente (sin conectar, permiso revocado).
  sinDrive,

  /// Sin Wi-Fi: el respaldo automático espera a la próxima ventana.
  sinWifi,

  /// Sin conexión de ningún tipo.
  sinConexion,

  /// Batería por debajo del 30 %.
  bateriaBaja,

  /// No hay DB abierta (sin sesión) o el motor no tiene respaldo armado.
  sinMotor,

  /// Ya hay un respaldo o una verificación corriendo.
  enCurso,

  /// Un respaldo automático falló hace poco: no se insiste en cada vuelta a la app.
  falloReciente,
}

/// Por qué falló un respaldo que se intentó.
enum CausaFalloRespaldo {
  /// Drive devolvió 401 o 403: la persona le quitó el permiso. El estado pasa a «Reconectar».
  permiso,

  /// El Drive de la persona no tiene espacio. El estado pasa a «sin espacio».
  sinEspacio,

  /// Cualquier otra: la red se cortó, Drive no contestó, la DEK no se pudo leer.
  otra,
}

/// Cómo terminó un pedido de respaldo.
sealed class ResultadoRespaldo {
  const ResultadoRespaldo();
}

/// Quedó subido a Drive.
final class RespaldoHecho extends ResultadoRespaldo {
  const RespaldoHecho({required this.fecha, required this.esBase});

  /// Cuándo se guardó en Drive.
  final DateTime fecha;

  /// `true` si fue una base completa; `false`, un incremental.
  final bool esBase;
}

/// No se intentó, con el motivo.
final class RespaldoOmitido extends ResultadoRespaldo {
  const RespaldoOmitido(this.motivo);

  final MotivoOmision motivo;
}

/// Se intentó y falló. Lo subido a medias no cuenta: la cadena anterior sigue vigente.
final class RespaldoFallido extends ResultadoRespaldo {
  const RespaldoFallido(this.causa);

  final CausaFalloRespaldo causa;
}

/// Cómo terminó una verificación de la cadena (HU-SYNC-009).
sealed class ResultadoVerificacion {
  const ResultadoVerificacion();
}

/// La cadena está entera (o todavía no hay nada que verificar).
final class CadenaIntegra extends ResultadoVerificacion {
  const CadenaIntegra({required this.hayRespaldo});

  final bool hayRespaldo;
}

/// Se encontró un problema: se regenera una base nueva, y [regeneracion] dice cómo salió.
final class CadenaConProblema extends ResultadoVerificacion {
  const CadenaConProblema({required this.problemas, required this.regeneracion});

  /// Los problemas, por nombre (`corrupt`, `brokenLink`…). Sin contenido.
  final Set<String> problemas;
  final ResultadoRespaldo regeneracion;
}

/// No se verificó, con el motivo.
final class VerificacionOmitida extends ResultadoVerificacion {
  const VerificacionOmitida(this.motivo);

  final MotivoOmision motivo;
}

/// La verificación no pudo mirar la cadena (sin red, Drive caído). No es un hallazgo: no cambia
/// nada y se vuelve a intentar.
final class VerificacionFallida extends ResultadoVerificacion {
  const VerificacionFallida(this.causa);

  final CausaFalloRespaldo causa;
}

/// El respaldo en Drive de la persona (HU-SYNC-005, HU-SYNC-009): lo que piden el cierre de la
/// jornada, la vuelta a la app, la conexión de Drive y el aviso de «lleva días sin respaldo».
///
/// Ninguna operación lanza: el respaldo es un seguro, y una falla suya no puede frenar lo que la
/// persona estaba haciendo. Dos pedidos a la vez no se pisan: el segundo vuelve con
/// [MotivoOmision.enCurso].
abstract interface class ServicioRespaldo {
  Future<ResultadoRespaldo> respaldar(OrigenRespaldo origen);

  /// La verificación periódica de la cadena. Si encuentra un problema, regenera la base.
  Future<ResultadoVerificacion> verificarIntegridad();
}
