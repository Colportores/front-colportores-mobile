import 'dart:convert';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/repositories/bloqueo_reenvio_verificacion_repository.dart';

/// [BloqueoReenvioVerificacionRepository] sobre el almacén seguro
/// (`ClaveSegura.bloqueoReenvioVerificacion`): un JSON `{"<correo>": "<vencimiento ISO 8601 UTC>"}`
/// que solo guarda los bloqueos vigentes (cada guardado descarta los que ya vencieron).
///
/// Serializa las operaciones: cada una espera a la anterior, así una lectura pedida después de un
/// guardado en vuelo ve el bloqueo nuevo, y dos guardados seguidos no se pisan (cada uno lee lo
/// que dejó el anterior). Un valor que no se puede leer (JSON roto, fecha rota) cuenta como «sin
/// bloqueo»: el candado es una comodidad de la pantalla, el límite de verdad lo aplica el servidor.
/// Sin el correo en los logs.
final class BloqueoReenvioVerificacionRepositoryImpl
    implements BloqueoReenvioVerificacionRepository {
  BloqueoReenvioVerificacionRepositoryImpl(this._almacen, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final AlmacenSeguro _almacen;
  final AppLogger _log;

  Future<void> _cola = Future<void>.value();

  Future<T> _encolar<T>(Future<T> Function() operacion) {
    final resultado = _cola.then((_) => operacion());
    _cola = resultado.then<void>((_) {}, onError: (Object _) {});
    return resultado;
  }

  /// Lo guardado, sin los pares que no se pueden leer.
  Future<Map<String, DateTime>> _leerGuardados() async {
    final valor = await _almacen.leer(ClaveSegura.bloqueoReenvioVerificacion);
    if (valor == null) return {};
    final Object? json;
    try {
      json = jsonDecode(valor);
    } on FormatException {
      return {};
    }
    if (json is! Map<String, dynamic>) return {};
    final bloqueos = <String, DateTime>{};
    for (final MapEntry(key: correo, value: vence) in json.entries) {
      if (correo.isEmpty || vence is! String) continue;
      final instante = DateTime.tryParse(vence.trim());
      if (instante != null) bloqueos[correo] = instante.toUtc();
    }
    return bloqueos;
  }

  /// Lo guardado, o nada si el almacén no se deja leer: al guardar, lo ilegible se pisa con lo
  /// nuevo, que es lo que importa.
  Future<Map<String, DateTime>> _leerGuardadosOVacio() async {
    try {
      return await _leerGuardados();
    } on Object {
      return {};
    }
  }

  @override
  Future<Map<String, DateTime>> leer() => _encolar(() async {
    try {
      return await _leerGuardados();
    } on Object catch (e) {
      _log.warn(
        LogModulo.auth,
        'VERIFICACION_BLOQUEO_LEER',
        'no se pudieron leer los bloqueos del reenvío de verificación',
        {'error': e.runtimeType.toString()},
      );
      return <String, DateTime>{};
    }
  });

  @override
  Future<void> guardar(String correo, DateTime vence, {required DateTime ahora}) =>
      _encolar(() async {
        try {
          final instante = ahora.toUtc();
          final guardados = await _leerGuardadosOVacio();
          final vigentes = <String, DateTime>{
            for (final MapEntry(key: otro, value: venceOtro) in guardados.entries)
              if (venceOtro.isAfter(instante)) otro: venceOtro,
            correo: vence.toUtc(),
          };
          await _almacen.escribir(
            ClaveSegura.bloqueoReenvioVerificacion,
            jsonEncode({
              for (final MapEntry(key: c, value: v) in vigentes.entries) c: v.toIso8601String(),
            }),
          );
        } on Object catch (e) {
          _log.warn(
            LogModulo.auth,
            'VERIFICACION_BLOQUEO_ESCRIBIR',
            'no se pudo guardar el bloqueo del reenvío de verificación',
            {'error': e.runtimeType.toString()},
          );
        }
      });
}

/// [BloqueoReenvioVerificacionRepository] en memoria: el default de los tests y de la app sin
/// Keystore. **No es código de producción**: `main.dart` lo reemplaza por
/// [BloqueoReenvioVerificacionRepositoryImpl].
final class BloqueoReenvioVerificacionEnMemoria implements BloqueoReenvioVerificacionRepository {
  BloqueoReenvioVerificacionEnMemoria([Map<String, DateTime> inicial = const {}])
    : _bloqueos = {for (final MapEntry(:key, :value) in inicial.entries) key: value.toUtc()};

  final Map<String, DateTime> _bloqueos;

  @override
  Future<Map<String, DateTime>> leer() async => Map.of(_bloqueos);

  @override
  Future<void> guardar(String correo, DateTime vence, {required DateTime ahora}) async {
    final instante = ahora.toUtc();
    _bloqueos.removeWhere((_, venceOtro) => !venceOtro.isAfter(instante));
    _bloqueos[correo] = vence.toUtc();
  }
}
