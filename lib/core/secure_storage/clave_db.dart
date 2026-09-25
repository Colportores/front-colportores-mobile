import 'dart:typed_data';

import 'envoltorio_dek.dart';

/// Buffer de 32 bytes con material secreto que se puede destruir. Base de [ClaveDb] y
/// [ClaveEnvoltorio]: son tipos distintos para que una no se pueda pasar donde va la otra (abrir la
/// DB con la clave del envoltorio, por ejemplo), pero se custodian igual.
///
/// **Se queda con el buffer que recibe, no lo copia**: es a propósito, porque [destruir] tiene que
/// poder pisar el original. Una copia defensiva dejaría los bytes de quien lo construyó vivos en
/// memoria después de cerrar sesión. Por lo mismo el buffer **tiene que ser mutable**: una vista
/// inmutable (`Uint8List.asUnmodifiableView()`) compila pero no se puede destruir, y el
/// constructor la rechaza con `ArgumentError` antes de que la clave llegue a usarse.
abstract base class _Clave32 {
  _Clave32(Uint8List bytes, this._nombre) : _bytes = bytes {
    if (bytes.length != bytesEsperados) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'la $_nombre debe tener $bytesEsperados bytes (256 bits)',
      );
    }
    try {
      // Prueba de escritura que no cambia nada: una vista inmutable lanza acá, no en destruir().
      bytes[0] = bytes[0];
    } on UnsupportedError {
      // Sin el valor a propósito: el mensaje del error no puede llevar los bytes de la clave.
      throw ArgumentError(
        'la $_nombre necesita un buffer mutable: destruir() tiene que poder sobrescribirlo',
        'bytes',
      );
    }
  }

  /// 256 bits (R-PV-03).
  static const int bytesEsperados = 32;

  final Uint8List _bytes;
  final String _nombre;
  bool _destruida = false;

  /// Bytes de la clave. Lanza `StateError` si ya se llamó a [destruir].
  Uint8List get bytes {
    if (_destruida) {
      throw StateError('la $_nombre ya fue destruida');
    }
    return _bytes;
  }

  /// Si la clave ya fue destruida y por lo tanto no sirve.
  bool get destruida => _destruida;

  /// Sobrescribe los bytes con ceros.
  ///
  /// Es **best-effort**: el recolector de la VM pudo haber copiado el buffer antes, así que esto
  /// achica la ventana pero no garantiza que la clave desaparezca de la RAM. Llamarlo dos veces
  /// es inofensivo.
  ///
  /// La marca se pone **antes** de sobrescribir: si el borrado fallara por lo que fuera, la clave
  /// queda inaccesible por [bytes] igual (falla cerrado), no viva detrás de un `destruida` en
  /// `false`.
  void destruir() {
    _destruida = true;
    _bytes.fillRange(0, _bytes.length, 0);
  }
}

/// DEK de la DB local: la clave AES-256 aleatoria con la que SQLCipher cifra el archivo (ADR-006,
/// R-PV-03).
///
/// **Nunca se persiste en claro.** Se genera con el CSPRNG del sistema en el primer login
/// (HU-AUTH-009) y se guarda solo envuelta: por el almacén seguro del equipo y, si hubo login con
/// contraseña, por Argon2id(contraseña) en un archivo aparte (`CustodiaClaveDb`). En claro vive en
/// memoria mientras la DB está abierta: al cerrar sesión se destruye con [destruir] y las copias
/// envueltas se conservan, para abrir la misma DB en el próximo login (HU-AUTH-006).
///
/// El tipo existe para que la clave no se confunda con un `Uint8List` cualquiera y para que
/// [toString] no la filtre a un log.
final class ClaveDb extends _Clave32 {
  ClaveDb(Uint8List bytes) : super(bytes, 'clave de la DB');

  /// 256 bits (R-PV-03).
  static const int bytesEsperados = _Clave32.bytesEsperados;

  @override
  String toString() => 'ClaveDb(oculta)';
}

/// Clave que envuelve la DEK con la contraseña: sale de Argon2id(contraseña, sal) y cifra la DEK en
/// el envoltorio que viaja con el backup (ADR-006). **No abre la DB**: por eso es otro tipo.
///
/// Vive lo justo para envolver o desenvolver, y se destruye enseguida.
final class ClaveEnvoltorio extends _Clave32 {
  ClaveEnvoltorio(Uint8List bytes) : super(bytes, 'clave del envoltorio');

  @override
  String toString() => 'ClaveEnvoltorio(oculta)';
}

/// Puerto que deriva, con Argon2id, la clave que **envuelve la DEK** desde la contraseña del usuario
/// (ADR-006). No deriva la clave de la DB: esa es la DEK, aleatoria.
///
/// La implementación de producción es `CriptoSodium` (libsodium, `crypto_pwhash` Argon2id v1.3).
/// Lo que tiene que cumplir cualquier implementación:
/// - Devolver 32 bytes en un buffer **mutable**, que [ClaveEnvoltorio] exige para poder destruirlo.
/// - Ser determinista: la misma contraseña con la misma sal y los mismos [ParametrosArgon2id] da la
///   misma clave, o el envoltorio no se vuelve a abrir.
/// - No bloquear el isolate de la UI: con los parámetros de ADR-006 tarda de 1 a 2 s (R13).
/// - No poner nunca la contraseña ni la clave en un log ni en el mensaje de una excepción.
/// - Lanzar una `Exception` si falla: el consumidor la traduce a `Failure`.
abstract interface class ProveedorClaveDb {
  /// Clave derivada de [password] y [sal] con [parametros]. Solo vive en memoria volátil.
  Future<ClaveEnvoltorio> derivar({
    required String password,
    required Uint8List sal,
    required ParametrosArgon2id parametros,
  });
}

/// Puerto que cifra la DEK con la [ClaveEnvoltorio] (cifrado autenticado), autenticando también la
/// cabecera del envoltorio: si alguien toca los parámetros o la sal, [abrir] falla.
///
/// La implementación de producción es `CriptoSodium`, con el algoritmo que nombra
/// [EnvoltorioDek.algoritmoActual].
abstract interface class SelladorDek {
  /// Cifra [dek] con [clave]. Devuelve el nonce (aleatorio, nuevo en cada llamada) y el cifrado.
  Future<({Uint8List nonce, Uint8List cifrado})> sellar({
    required ClaveDb dek,
    required ClaveEnvoltorio clave,
    required Uint8List cabecera,
  });

  /// Descifra la DEK. Lanza [EnvoltorioNoAbreException] si [clave] no es la que la cifró (otra
  /// contraseña) o si el envoltorio se alteró, y [EnvoltorioCorruptoException] si el nonce o el
  /// cifrado no pueden ser de un envoltorio.
  Future<ClaveDb> abrir({
    required Uint8List nonce,
    required Uint8List cifrado,
    required ClaveEnvoltorio clave,
    required Uint8List cabecera,
  });
}

/// Falla de la librería criptográfica al derivar o cifrar. [motivo] describe qué pasó y nunca lleva
/// la contraseña, la clave ni la DEK.
final class CriptoException implements Exception {
  const CriptoException(this.operacion, this.motivo);

  /// `derivar` o `sellar`.
  final String operacion;

  final String motivo;

  @override
  String toString() => 'CriptoException($operacion: $motivo)';
}
