import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/entities/estado_cuenta.dart';

/// Dónde recuerda la app el último estado de cuenta que informó el backend (HU-AUTH-008), con el
/// usuario: otra cuenta que entre en el mismo equipo no lo hereda.
abstract interface class EstadoCuentaLocalDataSource {
  Future<EstadoCuenta?> leer(String usuarioId);

  Future<void> guardar(String usuarioId, EstadoCuenta estado);
}

/// En el almacén seguro ([ClaveSegura.estadoCuenta]). Lanza `AlmacenSeguroException`.
final class EstadoCuentaEnAlmacen implements EstadoCuentaLocalDataSource {
  const EstadoCuentaEnAlmacen(this._almacen);

  final AlmacenSeguro _almacen;

  @override
  Future<EstadoCuenta?> leer(String usuarioId) async {
    final guardado = await _almacen.leer(ClaveSegura.estadoCuenta);
    if (guardado == null || !guardado.startsWith('$usuarioId:')) return null;
    final nombre = guardado.substring(usuarioId.length + 1);
    return EstadoCuenta.values.where((e) => e.name == nombre).firstOrNull;
  }

  @override
  Future<void> guardar(String usuarioId, EstadoCuenta estado) =>
      _almacen.escribir(ClaveSegura.estadoCuenta, '$usuarioId:${estado.name}');
}

/// En memoria, para la demo sin backend y los tests. **No es código de producción.**
final class EstadoCuentaLocalEnMemoria implements EstadoCuentaLocalDataSource {
  final _estados = <String, EstadoCuenta>{};

  @override
  Future<EstadoCuenta?> leer(String usuarioId) async => _estados[usuarioId];

  @override
  Future<void> guardar(String usuarioId, EstadoCuenta estado) async => _estados[usuarioId] = estado;
}
