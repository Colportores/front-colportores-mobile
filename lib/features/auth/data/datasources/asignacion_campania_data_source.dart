import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/asignacion_campania.dart';

/// De dónde sale la campaña y la zona a las que se asignó al colportor (vista 18, 18-A07). Igual
/// que el estado de cuenta, la fuente real es el BFF (ADR-013), que todavía no existe: espera a
/// docs-organizacion#22.
abstract interface class AsignacionCampaniaDataSource {
  /// `null` si no se conoce la asignación. Lanza `SinConexionException` o `ServidorException`
  /// (`auth_remote_data_source.dart`) si no se pudo consultar.
  Future<AsignacionCampania?> consultar();
}

/// Mientras el BFF no exponga la asignación: no hay de dónde sacarla. La pantalla «Ya te
/// asignaron» sale igual, sin los renglones de campaña y zona. **No es la regla de la HU**: se
/// reemplaza por el data source del BFF cuando exista.
final class AsignacionCampaniaSinFuente implements AsignacionCampaniaDataSource {
  AsignacionCampaniaSinFuente({AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  @override
  Future<AsignacionCampania?> consultar() async {
    _log.warn(
      LogModulo.auth,
      'ASIGNACION_SIN_FUENTE',
      'el BFF no expone la campaña y la zona asignadas',
    );
    return null;
  }
}
