import 'dart:convert';

import 'package:sync_engine/sync_engine.dart';

import '../../../../core/logging/app_logger.dart';

/// Cómo terminó de dejar el envoltorio de la clave en Drive.
enum ResultadoEnvoltorio {
  /// Se subió: no había uno, o el que había es de una contraseña anterior.
  subido,

  /// El de Drive ya es el de este teléfono.
  alDia,

  /// No se sube todavía: sin Drive conectado, sin envoltorio local, o con el envoltorio marcado como
  /// desactualizado por un cambio de contraseña a medias (#125). Ver [EnvoltorioEnDrive].
  omitido,

  /// Falló (sin red, sin permiso, Drive no contestó). El próximo respaldo lo reintenta.
  fallido,
}

/// La DEK envuelta con la contraseña (Argon2id), subida al `appDataFolder` junto al respaldo
/// (ADR-006: «viaja con el backup»; HU-SYNC-006).
///
/// **Para qué.** El respaldo va cifrado con la DEK. Si la persona pierde el teléfono, la DEK del
/// Keystore se pierde con él; lo único que queda es esta copia, abierta con la contraseña. Sin ella
/// no hay restauración en un teléfono nuevo.
///
/// **Cuándo se sube.** Después de cada respaldo y cuando cambia la contraseña (el envoltorio local
/// se rehace). Solo si el de Drive no es igual al local: no cuesta una subida por respaldo. Va
/// identificado por la llave de la cadena ([keyId]), así la restauración sabe cuál abre qué cadena.
/// Como la DEK es la misma, un envoltorio abre también los respaldos hechos antes de él.
///
/// **Qué no se sube.** Un envoltorio marcado como desactualizado (#125): se armó con una contraseña
/// que quizás ya no es la de la cuenta, y subirlo dejaría en Drive una copia que no abre con la
/// contraseña vigente. Nunca lanza: lo que falla se reintenta con el próximo respaldo.
final class EnvoltorioEnDrive {
  EnvoltorioEnDrive({
    required this._envoltorios,
    required this._keyId,
    required this._envoltorioLocal,
    required this._desactualizado,
    AppLogger? logger,
  }) : _log = logger ?? AppLogger.instance;

  /// Drive. `null` sin Drive conectado.
  final Future<KeyEnvelopePort?> Function() _envoltorios;

  /// El identificador de la llave de este teléfono (`CryptoPort.keyId`).
  final Future<String> Function() _keyId;

  /// El envoltorio de este teléfono, tal como se sube; `null` si no hay.
  final Future<String?> Function() _envoltorioLocal;

  /// Si el envoltorio local está marcado como desactualizado.
  final Future<bool> Function() _desactualizado;

  final AppLogger _log;

  Future<ResultadoEnvoltorio> sincronizar() async {
    try {
      final drive = await _envoltorios();
      if (drive == null) return ResultadoEnvoltorio.omitido;
      if (await _desactualizado()) {
        _log.info(LogModulo.backup, 'ENVOLTORIO_OMITIDO', 'el envoltorio está desactualizado');
        return ResultadoEnvoltorio.omitido;
      }
      final local = await _envoltorioLocal();
      if (local == null) return ResultadoEnvoltorio.omitido;

      final llave = await _keyId();
      final bytes = utf8.encode(local);
      final remoto = await drive.getEnvelope(llave);
      if (remoto != null && _iguales(remoto, bytes)) return ResultadoEnvoltorio.alDia;

      await drive.putEnvelope(llave, bytes);
      _log.info(LogModulo.backup, 'ENVOLTORIO_SUBIDO', 'envoltorio de la clave subido a Drive');
      return ResultadoEnvoltorio.subido;
    } on Object catch (e) {
      // Solo el tipo: el mensaje de Drive o del almacén puede traer datos de la cuenta.
      _log.warn(LogModulo.backup, 'ENVOLTORIO_FALLO', 'no se pudo dejar el envoltorio en Drive', {
        'error': e.runtimeType.toString(),
      });
      return ResultadoEnvoltorio.fallido;
    }
  }

  static bool _iguales(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
