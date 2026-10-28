import '../../../../core/logging/app_logger.dart';
import '../../../../datos/drift_sync_meta.dart';
import '../../domain/repositories/fecha_de_los_precios.dart';

/// [FechaDeLosPrecios] sobre `sync_meta`: la última bajada del motor (HU-SYNC-007, #486). El pull
/// baja el catálogo junto con todo lo demás, así que «los precios al día de la última bajada» es la
/// fecha del pull.
///
/// Si la tabla no se puede leer contesta `null` (no se sabe): la pantalla de precios abre igual.
final class FechaDeLosPreciosSyncMeta implements FechaDeLosPrecios {
  FechaDeLosPreciosSyncMeta(this._meta, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final DriftSyncMeta _meta;
  final AppLogger _log;

  @override
  Future<DateTime?> ultimaBajada() async {
    try {
      return (await _meta.read()).lastPullAt;
    } on Object catch (e) {
      _log.warn(LogModulo.sync, 'PRECIOS_FECHA_FAIL', 'no se pudo leer la última bajada', {
        'causa': e.runtimeType.toString(),
      });
      return null;
    }
  }
}
