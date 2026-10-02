import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/repositories/cambios_por_recuperacion.dart';

/// [CambiosPorRecuperacion] sobre el almacén seguro (`ClaveSegura.cambioPorRecuperacion`): el
/// instante, en ISO 8601 UTC. Lo último que esta corrida anotó manda sobre el almacén, que puede
/// no haber aceptado la escritura. Sin PII en logs.
final class CambiosPorRecuperacionEnAlmacen implements CambiosPorRecuperacion {
  CambiosPorRecuperacionEnAlmacen(this._almacen, {DateTime Function()? ahora, AppLogger? logger})
    : _ahora = ahora ?? DateTime.now,
      _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;
  final DateTime Function() _ahora;
  final AppLogger _log;

  DateTime? _enMemoria;

  @override
  Future<void> registrar() async {
    final ahora = _ahora().toUtc();
    _enMemoria = ahora;
    try {
      await _almacen.escribir(ClaveSegura.cambioPorRecuperacion, ahora.toIso8601String());
    } on Object catch (e) {
      _log.warn(LogModulo.auth, 'RECUPERACION_MARCA_ESCRIBIR', 'no se pudo guardar la marca', {
        'error': e.runtimeType.toString(),
      });
    }
  }

  @override
  Future<bool> hayUnoReciente() async {
    var cuando = _enMemoria;
    if (cuando == null) {
      try {
        final guardado = await _almacen.leer(ClaveSegura.cambioPorRecuperacion);
        cuando = guardado == null ? null : DateTime.tryParse(guardado)?.toUtc();
      } on Object catch (e) {
        _log.warn(LogModulo.auth, 'RECUPERACION_MARCA_LEER', 'no se pudo leer la marca', {
          'error': e.runtimeType.toString(),
        });
      }
    }
    return esReciente(cuando, _ahora());
  }
}

/// [CambiosPorRecuperacion] en memoria: el default de los tests y de la app sin Keystore.
/// **No es código de producción**: `main.dart` lo reemplaza por [CambiosPorRecuperacionEnAlmacen].
final class CambiosPorRecuperacionEnMemoria implements CambiosPorRecuperacion {
  CambiosPorRecuperacionEnMemoria({DateTime Function()? ahora}) : _ahora = ahora ?? DateTime.now;

  final DateTime Function() _ahora;
  DateTime? _cuando;

  @override
  Future<void> registrar() async => _cuando = _ahora().toUtc();

  @override
  Future<bool> hayUnoReciente() async => esReciente(_cuando, _ahora());
}

/// La regla: dentro de [CambiosPorRecuperacion.ventana] y no en el futuro.
bool esReciente(DateTime? cuando, DateTime ahora) {
  if (cuando == null) return false;
  final pasado = ahora.toUtc().difference(cuando);
  return !pasado.isNegative && pasado <= CambiosPorRecuperacion.ventana;
}
