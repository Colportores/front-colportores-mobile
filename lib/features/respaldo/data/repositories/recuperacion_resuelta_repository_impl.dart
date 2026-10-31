import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/repositories/recuperacion_resuelta_repository.dart';

/// [RecuperacionResueltaRepository] sobre el almacén seguro (`ClaveSegura.recuperacionResuelta`):
/// guarda el id del usuario que resolvió el asistente, nada más.
final class RecuperacionResueltaRepositoryImpl implements RecuperacionResueltaRepository {
  RecuperacionResueltaRepositoryImpl(this._almacen, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;
  final AppLogger _log;

  @override
  Future<bool> estaResuelta(String usuarioId) async =>
      await _almacen.leer(ClaveSegura.recuperacionResuelta) == usuarioId;

  @override
  Future<void> marcarResuelta(String usuarioId) async {
    try {
      await _almacen.escribir(ClaveSegura.recuperacionResuelta, usuarioId);
    } on Object catch (e) {
      _log.warn(
        LogModulo.backup,
        'RECUPERACION_MARCA',
        'no se pudo anotar que el asistente de recuperación se resolvió',
        {'error': e.runtimeType.toString()},
      );
    }
  }
}
