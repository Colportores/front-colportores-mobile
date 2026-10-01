import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/entities/estado_intentos_borrado.dart';
import '../../domain/repositories/intentos_borrado_repository.dart';

/// [IntentosBorradoRepository] sobre el almacén seguro (`ClaveSegura.intentosBorrado`), como
/// `<fallidos>|<fin de la espera en ISO 8601 UTC, o vacío>`. No es secreto: está ahí para no sumar
/// otro almacenamiento (igual que el estado de cuenta). Lo borra el borrado de datos locales.
final class IntentosBorradoRepositoryImpl implements IntentosBorradoRepository {
  IntentosBorradoRepositoryImpl(this._almacen, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;
  final AppLogger _log;

  @override
  Future<EstadoIntentosBorrado> leer() async {
    try {
      final valor = await _almacen.leer(ClaveSegura.intentosBorrado);
      if (valor == null) return EstadoIntentosBorrado.limpio;
      final partes = valor.split('|');
      if (partes.length != 2) return EstadoIntentosBorrado.limpio;
      final fallidos = int.tryParse(partes[0]);
      if (fallidos == null || fallidos < 0) return EstadoIntentosBorrado.limpio;
      return EstadoIntentosBorrado(
        fallidos: fallidos,
        bloqueadoHasta: partes[1].isEmpty ? null : DateTime.tryParse(partes[1]),
      );
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'WIPE_INTENTOS_LEER', 'no se pudo leer', const {}, e, st);
      return EstadoIntentosBorrado.limpio;
    }
  }

  @override
  Future<void> guardar(EstadoIntentosBorrado estado) async {
    try {
      await _almacen.escribir(
        ClaveSegura.intentosBorrado,
        '${estado.fallidos}|${estado.bloqueadoHasta?.toIso8601String() ?? ''}',
      );
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'WIPE_INTENTOS_ESCRIBIR', 'no se pudo guardar', const {}, e, st);
    }
  }

  @override
  Future<void> limpiar() async {
    try {
      await _almacen.borrar(ClaveSegura.intentosBorrado);
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'WIPE_INTENTOS_LIMPIAR', 'no se pudo limpiar', const {}, e, st);
    }
  }
}
