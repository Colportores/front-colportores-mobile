import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/catalogo_local.dart';
import '../../domain/repositories/consulta_de_precios_repository.dart';
import '../datasources/catalogo_local_data_source.dart';

/// [ConsultaDePreciosRepository] sobre la réplica local del catálogo de ventas (HU-CAT-006): solo lee
/// el teléfono, así que funciona sin conexión y se actualiza solo cuando el pull o el Realtime traen
/// algo.
///
/// Si la base no se puede leer, el `Stream` falla con [FailurePreciosNoDisponibles] (26·10) y nunca
/// emite un catálogo vacío: «no pude leer» no es «no hay precios». El detalle técnico queda en el
/// log, sin datos.
final class ConsultaDePreciosRepositoryImpl implements ConsultaDePreciosRepository {
  ConsultaDePreciosRepositoryImpl(this._datos, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final CatalogoLocalDataSource _datos;
  final AppLogger _log;

  @override
  Stream<CatalogoLocal> observar(String campaniaCiudadId) {
    return _datos.observar(campaniaCiudadId).handleError((Object error) {
      _log.warn(LogModulo.db, 'PRECIOS_LECTURA_FAIL', 'no se pudo leer el catálogo local', {
        'causa': error.runtimeType.toString(),
      });
      throw const FailurePreciosNoDisponibles();
    });
  }
}
