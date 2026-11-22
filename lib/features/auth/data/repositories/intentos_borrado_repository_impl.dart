import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/entities/estado_intentos_borrado.dart';
import '../../domain/repositories/intentos_borrado_repository.dart';
import '../../domain/usecases/verificar_password_borrado_use_case.dart';

/// [IntentosBorradoRepository] sobre el almacén seguro (`ClaveSegura.intentosBorrado`), como
/// `<fallidos>|<lo que falta de la espera, en milisegundos, o vacío>`. No es secreto: está ahí para
/// no sumar otro almacenamiento (igual que el estado de cuenta). Lo borra el borrado de datos
/// locales.
///
/// **La espera no se guarda como una hora**, sino como lo que falta, y se cuenta con el reloj
/// monótono de la corrida ([_ahora]): una hora guardada se compararía con la del sistema de la
/// corrida siguiente, y cerrar la app y adelantar la hora la saltearía (decisión de Cristian,
/// 02/10). A cambio, la espera solo corre mientras la app está viva: si se cierra, al volver
/// falta lo mismo que cuando se cerró. Falla cerrado, a propósito.
final class IntentosBorradoRepositoryImpl implements IntentosBorradoRepository {
  IntentosBorradoRepositoryImpl(this._almacen, this._ahora, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;

  /// Reloj monótono (`RelojMonotono`): el mismo que usa el caso de uso.
  final DateTime Function() _ahora;
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
      final restante = partes.length == 2 ? _restante(partes[1]) : null;
      if (fallidos == null || fallidos < 0 || restante == null || restante.isNegative) {
        // Mal formado: no se resetea (sería regalar intentos), se falla cerrado.
        _log.error(LogModulo.auth, 'WIPE_INTENTOS_FORMATO', 'valor guardado mal formado');
        return const EstadoIntentosBorrado.ilegible();
      }
      final estado = EstadoIntentosBorrado(
        fallidos: fallidos,
        bloqueadoHasta: restante == Duration.zero ? null : _ahora().add(restante),
      );
      _enMemoria = estado;
      return estado;
    } on Object catch (e, st) {
      _log.error(LogModulo.auth, 'WIPE_INTENTOS_LEER', 'no se pudo leer', const {}, e, st);
      return const EstadoIntentosBorrado.ilegible();
    }
  }

  /// Lo que falta de la espera según [guardado]: vacío = nada. Una hora ISO 8601 es el formato
  /// anterior de este valor: no se puede confiar en ella, así que se vuelve a esperar completo.
  Duration? _restante(String guardado) {
    if (guardado.isEmpty) return Duration.zero;
    final ms = int.tryParse(guardado);
    if (ms != null) return Duration(milliseconds: ms);
    if (DateTime.tryParse(guardado) != null) return VerificarPasswordBorradoUseCase.espera;
    return null;
  }

  @override
  Future<void> guardar(EstadoIntentosBorrado estado) async {
    _enMemoria = estado;
    final hasta = estado.bloqueadoHasta;
    final restante = hasta?.difference(_ahora());
    final faltan = restante == null || restante.isNegative ? '' : '${restante.inMilliseconds}';
    try {
      await _almacen.escribir(ClaveSegura.intentosBorrado, '${estado.fallidos}|$faltan');
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
