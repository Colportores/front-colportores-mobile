import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/repositories/modo_ahorro_repository.dart';

/// [ModoAhorroRepository] sobre el almacén seguro (`ClaveSegura.modoAhorroDatos`): `1` activo; sin
/// la clave, apagado. Leer nunca lanza (un almacén roto deja el modo apagado, el comportamiento
/// estándar, y queda en el log); guardar lanza si no pudo.
final class ModoAhorroRepositoryImpl implements ModoAhorroRepository {
  ModoAhorroRepositoryImpl(this._almacen, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;
  final AppLogger _log;

  static const _activo = '1';

  @override
  Future<bool> leer() async {
    try {
      return await _almacen.leer(ClaveSegura.modoAhorroDatos) == _activo;
    } on Object catch (e) {
      _log.warn(
        LogModulo.sync,
        'MODO_AHORRO_LEER',
        'no se pudo leer el modo ahorro de datos; queda apagado',
        {'error': e.runtimeType.toString()},
      );
      return false;
    }
  }

  @override
  Future<void> guardar({required bool activo}) async {
    if (activo) {
      await _almacen.escribir(ClaveSegura.modoAhorroDatos, _activo);
    } else {
      await _almacen.borrar(ClaveSegura.modoAhorroDatos);
    }
  }
}

/// [ModoAhorroRepository] en memoria: el default de los tests y de la app sin Keystore. **No es
/// código de producción**: `main.dart` lo reemplaza por [ModoAhorroRepositoryImpl].
final class ModoAhorroRepositoryEnMemoria implements ModoAhorroRepository {
  ModoAhorroRepositoryEnMemoria({this.activo = false});

  bool activo;

  /// Con `true`, guardar lanza (simula un almacén que falla al escribir).
  bool fallaAlGuardar = false;

  /// Cuántas veces se guardó.
  int guardados = 0;

  @override
  Future<bool> leer() async => activo;

  @override
  Future<void> guardar({required bool activo}) async {
    if (fallaAlGuardar) throw const AlmacenSeguroException(operacion: 'escribir');
    guardados++;
    this.activo = activo;
  }
}
