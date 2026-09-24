import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/services/reloj_sesion.dart';

/// [RelojSesion] que recuerda en el almacén seguro el instante más alto que vio
/// ([ClaveSegura.relojSesion]). Si el almacén falla, usa lo último que tiene en memoria: el
/// usuario no puede hacer nada con eso, así que solo va al log.
final class RelojSesionEnAlmacen implements RelojSesion {
  RelojSesionEnAlmacen(this._almacen, {DateTime Function()? sistema, AppLogger? logger})
    : _sistema = sistema ?? DateTime.now,
      _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;
  final DateTime Function() _sistema;
  final AppLogger _log;

  DateTime? _maximo;

  @override
  Future<DateTime> ahora() async {
    final maximo = await _maximoVisto();
    final sistema = _sistema().toUtc();
    if (maximo != null && !sistema.isAfter(maximo)) return maximo;
    await _guardar(sistema);
    return sistema;
  }

  @override
  Future<void> registrar(DateTime visto) async {
    final maximo = await _maximoVisto();
    if (maximo == null || visto.toUtc().isAfter(maximo)) await _guardar(visto.toUtc());
  }

  Future<DateTime?> _maximoVisto() async {
    try {
      final guardado = await _almacen.leer(ClaveSegura.relojSesion);
      final leido = guardado == null ? null : DateTime.tryParse(guardado)?.toUtc();
      if (leido != null && (_maximo == null || leido.isAfter(_maximo!))) _maximo = leido;
    } on Object catch (e) {
      _log.warn(LogModulo.auth, 'RELOJ_SESION_LEER_FAIL', 'se usa el reloj en memoria', {
        'error': e.runtimeType.toString(),
      });
    }
    return _maximo;
  }

  Future<void> _guardar(DateTime instante) async {
    _maximo = instante;
    try {
      await _almacen.escribir(ClaveSegura.relojSesion, instante.toIso8601String());
    } on Object catch (e) {
      _log.warn(LogModulo.auth, 'RELOJ_SESION_GUARDAR_FAIL', 'no se pudo guardar el reloj', {
        'error': e.runtimeType.toString(),
      });
    }
  }
}

/// [RelojSesion] en memoria, para la demo sin backend y los tests: [sistema] es el reloj del
/// equipo y se puede mover (también hacia atrás). **No es código de producción.**
final class RelojSesionEnMemoria implements RelojSesion {
  RelojSesionEnMemoria({DateTime Function()? sistema}) : sistema = sistema ?? DateTime.now;

  DateTime Function() sistema;
  DateTime? _maximo;

  @override
  Future<DateTime> ahora() async {
    final actual = sistema().toUtc();
    final maximo = _maximo;
    if (maximo != null && !actual.isAfter(maximo)) return maximo;
    return _maximo = actual;
  }

  @override
  Future<void> registrar(DateTime visto) async {
    final maximo = _maximo;
    if (maximo == null || visto.toUtc().isAfter(maximo)) _maximo = visto.toUtc();
  }
}
