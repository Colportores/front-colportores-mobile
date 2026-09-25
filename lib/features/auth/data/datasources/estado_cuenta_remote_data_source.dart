import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/estado_cuenta.dart';

/// De dónde sale el estado de la cuenta (HU-AUTH-008): el backend, por el BFF de la app
/// (ADR-013: los datos no se leen de PostgREST directo). El BFF identifica al usuario por el JWT.
///
/// Lanza `SinConexionException` sin red y `ServidorException` si el BFF responde con error
/// (`auth_remote_data_source.dart`).
abstract interface class EstadoCuentaRemoteDataSource {
  Future<EstadoCuenta> consultar();
}

/// Mientras el BFF no tenga el endpoint del estado de la cuenta (anotado en #62), la app con
/// Supabase no tiene de dónde sacarlo: sigue como hasta ahora, sin gate (todas las cuentas
/// activas), y lo deja en el log una vez por consulta. **No es la regla de la HU**: se reemplaza
/// por el data source del BFF cuando exista.
final class EstadoCuentaSinFuente implements EstadoCuentaRemoteDataSource {
  EstadoCuentaSinFuente({AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  @override
  Future<EstadoCuenta> consultar() async {
    _log.warn(LogModulo.auth, 'ESTADO_CUENTA_SIN_FUENTE', 'el BFF no expone el estado de cuenta');
    return EstadoCuenta.activa;
  }
}
