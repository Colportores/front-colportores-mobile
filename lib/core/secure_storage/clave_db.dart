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

/// Puerto que deriva la clave de la DB local desde la contraseña del usuario y la sal.
///
/// Lo consume el flujo de inicialización de HU-AUTH-009 (`DbLocalRepositoryImpl`), que después le
/// pasa la clave a `DatabaseHelper.abrir`: el helper recibe la clave ya derivada y no sabe de dónde
/// sale.
///
/// La implementación de producción deriva con **Argon2id** (ADR-003) y **todavía no existe**: qué
/// implementación de Argon2id se usa y con qué parámetros de costo es el Supuesto S11, pendiente de
/// decisión (#26). Hasta entonces `proveedorClaveDbProvider` no tiene implementación por defecto.
///
/// Lo que la implementación tiene que cumplir, venga de donde venga:
/// - Devolver 32 bytes (AES-256) en un buffer **mutable**, que [ClaveDb] exige para poder
///   destruirlo.
/// - Ser determinista: la misma contraseña con la misma sal da la misma clave, o la DB creada en
///   el primer login no se vuelve a abrir.
/// - No bloquear el isolate de la UI: la derivación tarda ~200–500 ms (HU-AUTH-009, riesgo R13).
/// - No poner nunca la contraseña ni la clave en un log ni en el mensaje de una excepción.
/// - Lanzar una `Exception` si falla: el consumidor la traduce a `Failure`.
abstract interface class ProveedorClaveDb {
  /// Clave derivada de [password] y [sal]. Solo vive en memoria volátil.
  Future<ClaveDb> derivar({required String password, required Uint8List sal});
}
