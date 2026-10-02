import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/repositories/cambios_por_recuperacion.dart';
import '../../domain/services/reloj_sesion.dart';

/// [CambiosPorRecuperacion] sobre el almacén seguro (`ClaveSegura.cambioPorRecuperacion`): el
/// instante, en ISO 8601 UTC. Lo último que esta corrida anotó manda sobre el almacén, que puede
/// no haber aceptado la escritura. Sin PII en logs.
///
/// La hora sale del [RelojSesion] (el de la ventana de 30 días de la sesión, HU-AUTH-007) y no de
/// `DateTime.now`: ese reloj no vuelve atrás, así que atrasar la hora del teléfono no deja la marca
/// en el futuro ni la estira de a saltos.
///
/// Las operaciones se ejecutan **en el orden en que se piden** (cola serial): un `otp_expired` que
/// llega justo después del cambio ya ve la marca, y un borrado pedido después de un registro lo
/// deja borrado.
final class CambiosPorRecuperacionEnAlmacen implements CambiosPorRecuperacion {
  CambiosPorRecuperacionEnAlmacen(this._almacen, this._reloj, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;
  final RelojSesion _reloj;
  final AppLogger _log;

  DateTime? _enMemoria;
  Future<void> _cola = Future<void>.value();

  Future<T> _encolar<T>(Future<T> Function() operacion) {
    final resultado = _cola.then((_) => operacion());
    _cola = resultado.then<void>((_) {}, onError: (Object _) {});
    return resultado;
  }

  @override
  Future<void> registrar() => _encolar(() async {
    try {
      final ahora = (await _reloj.ahora()).toUtc();
      _enMemoria = ahora;
      await _almacen.escribir(ClaveSegura.cambioPorRecuperacion, ahora.toIso8601String());
    } on Object catch (e) {
      _log.warn(LogModulo.auth, 'RECUPERACION_MARCA_ESCRIBIR', 'no se pudo guardar la marca', {
        'error': e.runtimeType.toString(),
      });
    }
  });

  @override
  Future<bool> hayUnoReciente() => _encolar(() async {
    try {
      var cuando = _enMemoria;
      if (cuando == null) {
        final guardado = await _almacen.leer(ClaveSegura.cambioPorRecuperacion);
        cuando = guardado == null ? null : DateTime.tryParse(guardado)?.toUtc();
      }
      return cuando != null && esReciente(cuando, await _reloj.ahora());
    } on Object catch (e) {
      _log.warn(LogModulo.auth, 'RECUPERACION_MARCA_LEER', 'no se pudo leer la marca', {
        'error': e.runtimeType.toString(),
      });
      return false;
    }
  });

  @override
  Future<void> olvidar() => _encolar(() async {
    _enMemoria = null;
    try {
      await _almacen.borrar(ClaveSegura.cambioPorRecuperacion);
    } on Object catch (e) {
      _log.warn(LogModulo.auth, 'RECUPERACION_MARCA_BORRAR', 'no se pudo borrar la marca', {
        'error': e.runtimeType.toString(),
      });
    }
  });
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

  @override
  Future<void> olvidar() async => _cuando = null;
}

/// La regla: dentro de [CambiosPorRecuperacion.ventana] y no en el futuro.
bool esReciente(DateTime? cuando, DateTime ahora) {
  if (cuando == null) return false;
  final pasado = ahora.toUtc().difference(cuando);
  return !pasado.isNegative && pasado <= CambiosPorRecuperacion.ventana;
}
