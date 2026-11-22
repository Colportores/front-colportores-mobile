import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/entities/cierre_forzado.dart';
import '../../domain/entities/motivo_expiracion.dart';
import '../../domain/repositories/cierre_forzado_repository.dart';

/// [CierreForzadoRepository] sobre el almacén seguro (`ClaveSegura.cierreForzado`), como
/// `<motivo>|<fecha ISO 8601 UTC>`.
///
/// Serializa las operaciones: cada una espera a la anterior, así un «guardar» que sigue en vuelo no
/// pisa a un «borrar» pedido después (entrar justo después de que se detecte un cierre). Un valor
/// que no se puede leer (motivo desconocido, fecha rota) se trata como «no hay cierre»: no se
/// inventa un aviso. Sin datos personales en logs.
final class CierreForzadoRepositoryImpl implements CierreForzadoRepository {
  CierreForzadoRepositoryImpl(this._almacen, {AppLogger? logger})
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
  Future<CierreForzado?> leer() => _encolar(() async {
    try {
      final valor = await _almacen.leer(ClaveSegura.cierreForzado);
      return valor == null ? null : _decodificar(valor);
    } on Object catch (e) {
      _log.warn(LogModulo.auth, 'CIERRE_FORZADO_LEER', 'no se pudo leer el motivo del cierre', {
        'error': e.runtimeType.toString(),
      });
      return null;
    }
  });

  @override
  Future<void> guardar(CierreForzado cierre) => _encolar(() async {
    try {
      await _almacen.escribir(ClaveSegura.cierreForzado, _codificar(cierre));
    } on Object catch (e) {
      _log.warn(
        LogModulo.auth,
        'CIERRE_FORZADO_ESCRIBIR',
        'no se pudo guardar el motivo del cierre',
        {'error': e.runtimeType.toString()},
      );
    }
  });

  @override
  Future<void> borrar() => _encolar(() async {
    try {
      await _almacen.borrar(ClaveSegura.cierreForzado);
    } on Object catch (e) {
      _log.warn(LogModulo.auth, 'CIERRE_FORZADO_BORRAR', 'no se pudo borrar el motivo del cierre', {
        'error': e.runtimeType.toString(),
      });
    }
  });

  static String _codificar(CierreForzado cierre) =>
      '${cierre.motivo.name}|${cierre.fecha.toIso8601String()}';

  static CierreForzado? _decodificar(String valor) {
    final partes = valor.trim().split('|');
    if (partes.length != 2) return null;
    final motivo = MotivoExpiracion.values.where((m) => m.name == partes[0]).firstOrNull;
    final fecha = DateTime.tryParse(partes[1]);
    if (motivo == null || fecha == null) return null;
    return CierreForzado(motivo: motivo, fecha: fecha);
  }
}

/// [CierreForzadoRepository] en memoria: el default de los tests y de la app sin Keystore.
/// **No es código de producción**: `main.dart` lo reemplaza por [CierreForzadoRepositoryImpl].
final class CierreForzadoEnMemoria implements CierreForzadoRepository {
  CierreForzadoEnMemoria([this._cierre]);

  CierreForzado? _cierre;

  @override
  Future<CierreForzado?> leer() async => _cierre;

  @override
  Future<void> guardar(CierreForzado cierre) async => _cierre = cierre;

  @override
  Future<void> borrar() async => _cierre = null;
}
