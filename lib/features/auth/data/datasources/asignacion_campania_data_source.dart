import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/asignacion_campania.dart';

/// De dónde sale la campaña y la zona a las que se asignó al colportor (vista 18, 18-A07). El
/// artboard se difiere: decisión de Cristian (02/10), el dato llega con #62 (la asignación sale
/// del pull de `campania_colportor`, sin BFF). Hasta entonces no hay fuente y no se inventa.
abstract interface class AsignacionCampaniaDataSource {
  /// `null` si no se conoce la asignación. Lanza `SinConexionException` o `ServidorException`
  /// (`auth_remote_data_source.dart`) si no se pudo consultar.
  Future<AsignacionCampania?> consultar();
}

/// Mientras no llegue #62: no hay de dónde sacar la asignación. La pantalla «Ya te asignaron»
/// sale igual, sin los renglones de campaña y zona. **No es la regla de la HU**: se reemplaza por
/// la lectura de la asignación cuando exista.
final class AsignacionCampaniaSinFuente implements AsignacionCampaniaDataSource {
  AsignacionCampaniaSinFuente({AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  @override
  Future<AsignacionCampania?> consultar() async {
    _log.warn(
      LogModulo.auth,
      'ASIGNACION_SIN_FUENTE',
      'sin fuente de la campaña y la zona asignadas (llega con #62)',
    );
    return null;
  }
}
