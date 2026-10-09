import 'dart:convert';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../domain/repositories/zonas_avisadas_repository.dart';

/// [ZonasAvisadasRepository] sobre el almacén seguro (`ClaveSegura.zonasAvisadas`): un JSON
/// `{"<inscripción>": "<zona>" | null}`.
///
/// Serializa las operaciones: cada una espera a la anterior, así una lectura pedida después de una
/// anotación en vuelo ve lo nuevo, y dos anotaciones seguidas no se pisan (cada una lee lo que dejó
/// la anterior). Un valor que no se puede leer (JSON roto) cuenta como «nada avisado todavía»: lo
/// peor es repetir un aviso. Sin ids en los logs.
final class ZonasAvisadasRepositoryImpl implements ZonasAvisadasRepository {
  ZonasAvisadasRepositoryImpl(this._almacen, {AppLogger? logger})
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
  Future<Map<String, String?>> _leerGuardadas() async {
    final valor = await _almacen.leer(ClaveSegura.zonasAvisadas);
    if (valor == null) return {};
    final Object? json;
    try {
      json = jsonDecode(valor);
    } on FormatException {
      return {};
    }
    if (json is! Map<String, dynamic>) return {};
    final avisadas = <String, String?>{};
    for (final MapEntry(key: inscripcion, value: zona) in json.entries) {
      if (inscripcion.isEmpty) continue;
      if (zona == null) {
        avisadas[inscripcion] = null;
      } else if (zona is String && zona.isNotEmpty) {
        avisadas[inscripcion] = zona;
      }
    }
    return avisadas;
  }

  /// Lo guardado, o nada si el almacén no se deja leer: al anotar, lo ilegible se pisa con lo nuevo.
  Future<Map<String, String?>> _leerGuardadasOVacio() async {
    try {
      return await _leerGuardadas();
    } on Object {
      return {};
    }
  }

  @override
  Future<Map<String, String?>> leer() => _encolar(() async {
    try {
      return await _leerGuardadas();
    } on Object catch (e) {
      _log.warn(LogModulo.auth, 'ZONA_AVISADA_LEER', 'no se pudieron leer las zonas ya avisadas', {
        'error': e.runtimeType.toString(),
      });
      return <String, String?>{};
    }
  });

  @override
  Future<void> anotar(Map<String, String?> avisadas) {
    if (avisadas.isEmpty) return Future<void>.value();
    return _encolar(() async {
      try {
        final guardadas = await _leerGuardadasOVacio();
        await _almacen.escribir(ClaveSegura.zonasAvisadas, jsonEncode({...guardadas, ...avisadas}));
      } on Object catch (e) {
        _log.warn(
          LogModulo.auth,
          'ZONA_AVISADA_ESCRIBIR',
          'no se pudieron guardar las zonas ya avisadas',
          {'error': e.runtimeType.toString()},
        );
      }
    });
  }
}

/// [ZonasAvisadasRepository] en memoria: el default de los tests y de la app sin Keystore.
/// **No es código de producción**: `main.dart` lo reemplaza por [ZonasAvisadasRepositoryImpl].
final class ZonasAvisadasEnMemoria implements ZonasAvisadasRepository {
  ZonasAvisadasEnMemoria([Map<String, String?> inicial = const {}]) : _avisadas = {...inicial};

  final Map<String, String?> _avisadas;

  /// Con `true`, [anotar] no guarda nada (simula un almacén que falla).
  bool fallaAlAnotar = false;

  @override
  Future<Map<String, String?>> leer() async => {..._avisadas};

  @override
  Future<void> anotar(Map<String, String?> avisadas) async {
    if (fallaAlAnotar) return;
    _avisadas.addAll(avisadas);
  }
}
