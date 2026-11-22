import '../../../../core/logging/app_logger.dart';
import '../../domain/repositories/fecha_de_los_precios.dart';
import '../../domain/services/antiguedad_de_precios.dart';
import '../datasources/catalogo_local_data_source.dart';

/// [DiasDeAntiguedadDePrecios] sobre la réplica de `parametro_global` (backend-supabase 0070,
/// decisión de Cristian, 23/10, «Precio viejo»): los días que Administración fijó para que el aviso
/// de Precios se ponga fuerte.
///
/// **Nunca falla ni frena nada**: el aviso fuerte no impide vender. Si la fila todavía no bajó, está
/// dada de baja, trae un valor que no sirve (menos de 1) o la base no se pudo leer, rigen los
/// [AntiguedadDePrecios.diasPorDefecto] de siempre.
final class DiasDeAntiguedadDePreciosLocal implements DiasDeAntiguedadDePrecios {
  DiasDeAntiguedadDePreciosLocal(this._datos, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final CatalogoLocalDataSource _datos;
  final AppLogger _log;

  @override
  Future<int> dias() async {
    try {
      final valor = await _datos.diasDeAntiguedadDeLosPrecios();
      return valor != null && valor >= 1 ? valor : AntiguedadDePrecios.diasPorDefecto;
    } on Object catch (e) {
      _log.warn(
        LogModulo.db,
        'PRECIOS_DIAS_FAIL',
        'no se pudo leer los días del aviso de precios',
        {'causa': e.runtimeType.toString()},
      );
      return AntiguedadDePrecios.diasPorDefecto;
    }
  }
}
