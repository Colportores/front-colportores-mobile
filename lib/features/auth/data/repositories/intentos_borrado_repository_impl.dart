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

  /// Lo último que esta corrida guardó o limpió: manda sobre el almacén, que puede no haber
  /// aceptado la escritura. Así un intento que no se pudo escribir igual cuenta.
  EstadoIntentosBorrado? _enMemoria;

  @override
  Future<EstadoIntentosBorrado> leer() async {
    final memoria = _enMemoria;
    if (memoria != null) return memoria;
    try {
      final valor = await _almacen.leer(ClaveSegura.intentosBorrado);
      if (valor == null) return EstadoIntentosBorrado.limpio;
      final partes = valor.split('|');
      final fallidos = partes.length == 2 ? int.tryParse(partes[0]) : null;
      final hasta = partes.length == 2 && partes[1].isNotEmpty
          ? DateTime.tryParse(partes[1])
          : null;
      if (fallidos == null || fallidos < 0 || (partes[1].isNotEmpty && hasta == null)) {
        // Mal formado: no se resetea (sería regalar intentos), se falla cerrado.
        _log.error(LogModulo.auth, 'WIPE_INTENTOS_FORMATO', 'valor guardado mal formado');
        return const EstadoIntentosBorrado.ilegible();
      }
      return EstadoIntentosBorrado(fallidos: fallidos, bloqueadoHasta: hasta);
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'WIPE_INTENTOS_LEER', 'no se pudo leer', const {}, e, st);
      return const EstadoIntentosBorrado.ilegible();
    }
  }

  @override
  Future<void> guardar(EstadoIntentosBorrado estado) async {
    _enMemoria = estado;
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
    _enMemoria = EstadoIntentosBorrado.limpio;
    try {
      await _almacen.borrar(ClaveSegura.intentosBorrado);
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'WIPE_INTENTOS_LIMPIAR', 'no se pudo limpiar', const {}, e, st);
    }
  }
}
