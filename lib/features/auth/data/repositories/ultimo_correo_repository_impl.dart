import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/repositories/ultimo_correo_repository.dart';

/// [UltimoCorreoRepository] sobre el almacén seguro (`ClaveSegura.ultimoCorreo`).
///
/// Serializa las operaciones: cada una espera a la anterior, así un «guardar» que sigue en vuelo
/// no pisa a un «borrar» pedido después (cerrar sesión justo después de entrar). Sin PII en logs:
/// el correo nunca va al log.
final class UltimoCorreoRepositoryImpl implements UltimoCorreoRepository {
  UltimoCorreoRepositoryImpl(this._almacen, {AppLogger? logger})
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
  Future<String?> leer() => _encolar(() async {
    try {
      final valor = (await _almacen.leer(ClaveSegura.ultimoCorreo))?.trim();
      return valor == null || valor.isEmpty ? null : valor;
    } on Object catch (e) {
      _log.warn(LogModulo.auth, 'ULTIMO_CORREO_LEER', 'no se pudo leer el último correo', {
        'error': e.runtimeType.toString(),
      });
      return null;
    }
  });

  @override
  Future<void> guardar(String email) => _encolar(() async {
    final limpio = email.trim();
    if (limpio.isEmpty) return;
    try {
      await _almacen.escribir(ClaveSegura.ultimoCorreo, limpio);
    } on Object catch (e) {
      _log.warn(LogModulo.auth, 'ULTIMO_CORREO_ESCRIBIR', 'no se pudo guardar el último correo', {
        'error': e.runtimeType.toString(),
      });
    }
  });

  @override
  Future<void> borrar() => _encolar(() async {
    try {
      await _almacen.borrar(ClaveSegura.ultimoCorreo);
    } on Object catch (e) {
      _log.warn(LogModulo.auth, 'ULTIMO_CORREO_BORRAR', 'no se pudo borrar el último correo', {
        'error': e.runtimeType.toString(),
      });
    }
  });
}

/// [UltimoCorreoRepository] en memoria: el default de los tests y de la app sin Keystore.
/// **No es código de producción**: `main.dart` lo reemplaza por [UltimoCorreoRepositoryImpl].
final class UltimoCorreoEnMemoria implements UltimoCorreoRepository {
  UltimoCorreoEnMemoria([this._correo]);

  String? _correo;

  @override
  Future<String?> leer() async => _correo;

  @override
  Future<void> guardar(String email) async {
    final limpio = email.trim();
    if (limpio.isNotEmpty) _correo = limpio;
  }

  @override
  Future<void> borrar() async => _correo = null;
}
