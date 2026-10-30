import '../../domain/services/servicio_respaldo.dart';

/// Lo que la app revisa al arrancar y cada vez que vuelve al frente (HU-SYNC-005, HU-SYNC-009):
/// un respaldo si lleva más de 24 horas sin uno (el fallback de iOS, R30, donde el sistema no
/// garantiza los trabajos nocturnos), y la verificación de la cadena si pasaron 7 días desde la
/// última.
///
/// Las condiciones (Drive conectado, Wi-Fi, batería) las pone [ServicioRespaldo]: acá solo se decide
/// si **toca**. Nada lanza.
final class RevisionDelRespaldo {
  RevisionDelRespaldo({
    required this.servicio,
    required this.ultimoRespaldo,
    required this.ultimaVerificacion,
    DateTime Function()? ahora,
    this.cadaCuantoRespaldar = const Duration(hours: 24),
    this.cadaCuantoVerificar = const Duration(days: 7),
  }) : _ahora = ahora ?? (() => DateTime.now().toUtc());

  final ServicioRespaldo servicio;

  /// Cuándo fue el último respaldo (`SyncStatus.lastBackupAt`), o `null` si nunca hubo.
  final Future<DateTime?> Function() ultimoRespaldo;

  /// Cuándo fue la última verificación (`audit_log`), o `null` si nunca se hizo.
  final Future<DateTime?> Function() ultimaVerificacion;

  final DateTime Function() _ahora;
  final Duration cadaCuantoRespaldar;
  final Duration cadaCuantoVerificar;

  Future<void> revisar() async {
    try {
      final ultimo = await ultimoRespaldo();
      if (_toca(ultimo, cadaCuantoRespaldar)) {
        await servicio.respaldar(OrigenRespaldo.alAbrir);
      }
      final verificada = await ultimaVerificacion();
      if (_toca(verificada, cadaCuantoVerificar)) {
        await servicio.verificarIntegridad();
      }
    } on Object {
      // Leer las fechas falló: se vuelve a mirar la próxima vez que la app vuelva al frente.
    }
  }

  bool _toca(DateTime? ultima, Duration cada) =>
      ultima == null || _ahora().difference(ultima) >= cada;
}
