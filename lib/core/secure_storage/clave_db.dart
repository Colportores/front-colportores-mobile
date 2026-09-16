import 'dart:typed_data';

/// Clave AES-256 con la que se abre la DB local cifrada (SQLCipher — ADR-003, R-PV-03).
///
/// **Nunca se persiste.** Se deriva de la contraseña del usuario más la sal que custodia
/// `CustodiaClaveDb`, y vive solo en memoria volátil mientras la sesión está activa
/// (HU-AUTH-009). Al cerrar sesión se destruye con [destruir] y la sal se conserva, para poder
/// re-derivarla en el próximo login y abrir la misma DB sin restore (HU-AUTH-006).
///
/// El tipo existe para que la clave no se confunda con un `Uint8List` cualquiera y para que
/// [toString] no la filtre a un log.
///
/// **Se queda con el buffer que recibe, no lo copia**: es a propósito, porque [destruir] tiene que
/// poder pisar el original. Una copia defensiva dejaría los bytes de quien lo construyó vivos en
/// memoria después de cerrar sesión. Por lo mismo el buffer **tiene que ser mutable**: una vista
/// inmutable (`Uint8List.asUnmodifiableView()`) compila pero no se puede destruir, y el
/// constructor la rechaza con `ArgumentError` antes de que la clave llegue a usarse.
final class ClaveDb {
  ClaveDb(Uint8List bytes) : _bytes = bytes {
    if (bytes.length != bytesEsperados) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'la clave de la DB debe tener $bytesEsperados bytes (AES-256)',
      );
    }
    try {
      // Prueba de escritura que no cambia nada: una vista inmutable lanza acá, no en destruir().
      bytes[0] = bytes[0];
    } on UnsupportedError {
      // Sin el valor a propósito: el mensaje del error no puede llevar los bytes de la clave.
      throw ArgumentError(
        'la clave de la DB necesita un buffer mutable: destruir() tiene que poder sobrescribirlo',
        'bytes',
      );
    }
  }

  /// 256 bits (R-PV-03).
  static const int bytesEsperados = 32;

  final Uint8List _bytes;
  bool _destruida = false;

  /// Bytes de la clave. Lanza `StateError` si ya se llamó a [destruir].
  Uint8List get bytes {
    if (_destruida) {
      throw StateError('la clave de la DB ya fue destruida');
    }
    return _bytes;
  }

  /// Si la clave ya fue destruida y por lo tanto no sirve para abrir la DB.
  bool get destruida => _destruida;

  /// Sobrescribe los bytes con ceros al cerrar sesión (HU-AUTH-006).
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

  @override
  String toString() => 'ClaveDb(oculta)';
}

/// Puerto con el que la DB local cifrada pide su clave.
///
/// Es la superficie que `DatabaseHelper` (#6) consume: pide la clave y no sabe de dónde sale.
/// La implementación de producción deriva con **Argon2id** desde la contraseña del usuario y la
/// sal de `CustodiaClaveDb` (ADR-003). Esa derivación **no** es parte de este wrapper: llega con
/// HU-AUTH-009 (#27), donde también se cierra el Supuesto S11 —qué implementación de Argon2id se
/// usa— y se fijan sus parámetros de costo.
abstract interface class ProveedorClaveDb {
  /// Clave con la que abrir la DB local. Solo vive en memoria volátil.
  Future<ClaveDb> claveDb();
}
