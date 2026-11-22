import 'dart:async';
import 'dart:convert';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/repositories/aviso_privacidad_repository.dart';

/// [AvisoPrivacidadRepository] sobre el almacén seguro (`ClaveSegura.avisoPrivacidadOculto`): un JSON
/// con la lista de ids (UUID) de las cuentas que escondieron el aviso. Nada más: ni correos ni
/// nombres.
///
/// Serializa las operaciones: cada una espera a la anterior, así dos cambios seguidos (esconder y
/// volver a mostrar) no se pisan y una lectura pedida después de un cambio en vuelo ve lo nuevo. Un
/// valor ilegible (JSON roto) cuenta como «nadie lo escondió»: lo peor es mostrar el aviso de más. Sin
/// ids en los logs.
final class AvisoPrivacidadRepositoryImpl implements AvisoPrivacidadRepository {
  AvisoPrivacidadRepositoryImpl(this._almacen, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;
  final AppLogger _log;

  Future<void> _cola = Future<void>.value();

  Future<T> _encolar<T>(Future<T> Function() operacion) {
    final resultado = _cola.then((_) => operacion());
    _cola = resultado.then<void>((_) {}, onError: (Object _) {});
    return resultado;
  }

  /// Las cuentas guardadas, sin lo que no se pueda leer.
  Future<Set<String>> _leerGuardadas() async {
    final valor = await _almacen.leer(ClaveSegura.avisoPrivacidadOculto);
    if (valor == null) return {};
    final Object? json;
    try {
      json = jsonDecode(valor);
    } on FormatException {
      return {};
    }
    if (json is! List<dynamic>) return {};
    return {
      for (final cuenta in json)
        if (cuenta is String && cuenta.isNotEmpty) cuenta,
    };
  }

  /// Lo guardado, o nada si el almacén no se deja leer: al escribir, lo ilegible se pisa con lo nuevo.
  Future<Set<String>> _leerGuardadasOVacio() async {
    try {
      return await _leerGuardadas();
    } on Object {
      return {};
    }
  }

  @override
  Future<bool> estaOculto(String cuentaId) => _encolar(() async {
    try {
      return (await _leerGuardadas()).contains(cuentaId);
    } on Object catch (e) {
      _log.warn(
        LogModulo.db,
        'AVISO_PRIVACIDAD_LEER',
        'no se pudo leer si el aviso de privacidad está escondido',
        {'error': e.runtimeType.toString()},
      );
      return false;
    }
  });

  Future<void> _cambiar(String cuentaId, {required bool oculto}) => _encolar(() async {
    try {
      final cuentas = await _leerGuardadasOVacio();
      final cambio = oculto ? cuentas.add(cuentaId) : cuentas.remove(cuentaId);
      // Sin cambio no se escribe; salvo que el valor guardado no se pudiera leer, que se arregla.
      if (!cambio) return;
      if (cuentas.isEmpty) {
        await _almacen.borrar(ClaveSegura.avisoPrivacidadOculto);
      } else {
        await _almacen.escribir(ClaveSegura.avisoPrivacidadOculto, jsonEncode(cuentas.toList()));
      }
    } on Object catch (e) {
      _log.warn(
        LogModulo.db,
        'AVISO_PRIVACIDAD_ESCRIBIR',
        'no se pudo guardar el aviso de privacidad',
        {'error': e.runtimeType.toString()},
      );
      rethrow;
    }
  });

  @override
  Future<void> ocultar(String cuentaId) => _cambiar(cuentaId, oculto: true);

  @override
  Future<void> mostrar(String cuentaId) => _cambiar(cuentaId, oculto: false);
}

/// [AvisoPrivacidadRepository] en memoria: el default de los tests y de la app sin Keystore.
/// **No es código de producción**: `main.dart` lo reemplaza por [AvisoPrivacidadRepositoryImpl].
final class AvisoPrivacidadEnMemoria implements AvisoPrivacidadRepository {
  AvisoPrivacidadEnMemoria([Iterable<String> ocultas = const []]) : _ocultas = {...ocultas};

  final Set<String> _ocultas;

  /// Con `true`, [estaOculto] devuelve `false` (simula un almacén ilegible).
  bool fallaAlLeer = false;

  /// Con `true`, [ocultar] y [mostrar] lanzan y no guardan nada (simula un almacén que falla).
  bool fallaAlEscribir = false;

  /// Si no es `null`, [ocultar] y [mostrar] esperan a que se complete (simula una escritura lenta).
  Completer<void>? compuerta;

  /// Cuántas veces se pidió escribir (con o sin éxito).
  int escrituras = 0;

  /// Las cuentas que lo tienen escondido ahora.
  Set<String> get ocultas => {..._ocultas};

  @override
  Future<bool> estaOculto(String cuentaId) async => !fallaAlLeer && _ocultas.contains(cuentaId);

  Future<void> _escribir(void Function() cambio) async {
    escrituras++;
    final espera = compuerta;
    if (espera != null) await espera.future;
    if (fallaAlEscribir) throw StateError('el almacén no deja escribir');
    cambio();
  }

  @override
  Future<void> ocultar(String cuentaId) => _escribir(() => _ocultas.add(cuentaId));

  @override
  Future<void> mostrar(String cuentaId) => _escribir(() => _ocultas.remove(cuentaId));
}
