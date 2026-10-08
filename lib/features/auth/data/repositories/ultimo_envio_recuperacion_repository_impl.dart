import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/repositories/ultimo_envio_recuperacion_repository.dart';

/// [UltimoEnvioRecuperacionRepository] sobre el almacén seguro
/// (`ClaveSegura.ultimoEnvioRecuperacion`), como fecha ISO 8601 en UTC.
///
/// Serializa las operaciones: cada una espera a la anterior, así una lectura pedida después de un
/// guardado en vuelo ve la hora nueva. Un valor que no se puede leer (fecha rota) se trata como
/// «no hay envío»: la espera es una comodidad de la pantalla, no el límite (lo aplica el
/// servidor). Sin el correo ni datos personales en logs.
final class UltimoEnvioRecuperacionRepositoryImpl implements UltimoEnvioRecuperacionRepository {
  UltimoEnvioRecuperacionRepositoryImpl(this._almacen, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;
  final AppLogger _log;

  Future<void> _cola = Future<void>.value();

  Future<T> _encolar<T>(Future<T> Function() operacion) {
    final resultado = _cola.then((_) => operacion());
    _cola = resultado.then<void>((_) {}, onError: (Object _) {});
    return resultado;
  }

  @override
  Future<DateTime?> leer() => _encolar(() async {
    try {
      final valor = await _almacen.leer(ClaveSegura.ultimoEnvioRecuperacion);
      return valor == null ? null : DateTime.tryParse(valor.trim())?.toUtc();
    } on Object catch (e) {
      _log.warn(
        LogModulo.auth,
        'RECUPERACION_ULTIMO_ENVIO_LEER',
        'no se pudo leer la hora del último enlace pedido',
        {'error': e.runtimeType.toString()},
      );
      return null;
    }
  });

  @override
  Future<void> guardar(DateTime cuando) => _encolar(() async {
    try {
      await _almacen.escribir(
        ClaveSegura.ultimoEnvioRecuperacion,
        cuando.toUtc().toIso8601String(),
      );
    } on Object catch (e) {
      _log.warn(
        LogModulo.auth,
        'RECUPERACION_ULTIMO_ENVIO_ESCRIBIR',
        'no se pudo guardar la hora del último enlace pedido',
        {'error': e.runtimeType.toString()},
      );
    }
  });
}

/// [UltimoEnvioRecuperacionRepository] en memoria: el default de los tests y de la app sin
/// Keystore. **No es código de producción**: `main.dart` lo reemplaza por
/// [UltimoEnvioRecuperacionRepositoryImpl].
final class UltimoEnvioRecuperacionEnMemoria implements UltimoEnvioRecuperacionRepository {
  UltimoEnvioRecuperacionEnMemoria([this._cuando]);

  DateTime? _cuando;

  @override
  Future<DateTime?> leer() async => _cuando;

  @override
  Future<void> guardar(DateTime cuando) async => _cuando = cuando.toUtc();
}
