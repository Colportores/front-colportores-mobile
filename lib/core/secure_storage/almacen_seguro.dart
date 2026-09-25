/// Inventario de secretos que la app guarda en el almacén seguro del dispositivo.
///
/// El enum es cerrado a propósito: agregar un secreto obliga a declararlo acá, así el inventario
/// completo de lo que la app guarda en Keystore/Keychain se lee de un solo lugar.
///
/// El [id] es el nombre real con el que el secreto queda escrito en el dispositivo. **Cambiarlo
/// deja huérfano lo ya guardado** en los equipos que lo tienen: para la DEK eso significa una DB
/// local que ya no se abre sola (queda la recuperación con la contraseña, ADR-006).
enum ClaveSegura {
  /// DEK de la DB local: la clave aleatoria de 256 bits con la que SQLCipher cifra el archivo
  /// (ADR-006), en base64. Es la copia envuelta por el almacén del equipo —Keystore en Android,
  /// Keychain en iOS—, la que deja abrir la DB sin pedir la contraseña. La otra copia, envuelta con
  /// la contraseña, vive fuera de este almacén (`ArchivoEnvoltorioDek`).
  dekDb('db_dek'),

  /// Marca de que la DB local ya se creó y migró en este dispositivo (HU-AUTH-009).
  dbInicializada('db_initialized'),

  /// El usuario aceptó seguir con un Keystore por software (Supuesto S10, HU-AUTH-009): la
  /// elección queda registrada acá.
  consentimientoAlmacenSoftware('keystore_software_aceptado'),

  /// Último estado de cuenta que informó el backend, con el usuario (`<uuid>:<estado>`,
  /// HU-AUTH-008). No es secreto: vive acá para no sumar otro almacenamiento, y así el borrado de
  /// datos locales (HU-AUTH-010) también lo borra.
  estadoCuenta('account_state');

  const ClaveSegura(this.id);

  /// Nombre con el que el secreto se escribe en el almacén del dispositivo.
  final String id;
}

/// Almacén seguro del dispositivo: Android Keystore / iOS Keychain (§8.2.1).
///
/// Es el **único** lugar donde la app guarda material secreto en el equipo, y todo lo que guarda
/// está inventariado en [ClaveSegura]: la DEK de la DB local, la marca de inicialización y el
/// consentimiento de S10; la sesión de auth (el JWT) también va a vivir acá cuando
/// `AuthLocalDataSource` tenga implementación real (ADR-006).
///
/// Puerto en Dart puro; la implementación que conoce el plugin es `AlmacenSeguroKeystore` y la de
/// tests es `AlmacenSeguroEnMemoria`. Igual que los data sources de auth, **el almacén lanza
/// excepciones** ([AlmacenSeguroException]) y es su consumidor quien las traduce a `Failure`.
abstract interface class AlmacenSeguro {
  /// Valor guardado para [clave], o `null` si nunca se escribió.
  Future<String?> leer(ClaveSegura clave);

  /// Guarda [valor] para [clave], reemplazando lo que hubiera.
  Future<void> escribir(ClaveSegura clave, String valor);

  /// Borra [clave]. Si no existía, no hace nada.
  Future<void> borrar(ClaveSegura clave);

  /// Borra **todo** lo que este almacén custodia para la app —cada [ClaveSegura], no solo la DEK:
  /// también la marca de inicialización y, cuando esté, la sesión de auth—. Lo usan el derecho al
  /// borrado (HU-AUTH-010) y la recuperación guiada de ADR-006, que limpia el almacén antes de
  /// reescribirlo. Para borrar un solo secreto está [borrar].
  Future<void> borrarTodo();
}

/// Falla del almacén seguro del dispositivo: Keystore/Keychain ausente, bloqueado o roto.
///
/// Con `resetOnError: false` (ADR-006) el plugin ya no borra nada por su cuenta: la falla llega
/// hasta acá y es la app la que decide qué hacer (recuperar con la contraseña, o preguntar antes
/// de empezar de nuevo).
///
/// [toString] nunca incluye el valor guardado: solo la operación y el nombre de la clave.
final class AlmacenSeguroException implements Exception {
  const AlmacenSeguroException({required this.operacion, this.clave, this.causa});

  /// Operación que falló: `leer`, `escribir`, `borrar` o `borrarTodo`.
  final String operacion;

  /// Clave involucrada, o `null` en las operaciones que no apuntan a una sola.
  final ClaveSegura? clave;

  /// Error original de la plataforma. Va a logs, nunca al usuario.
  final Object? causa;

  @override
  String toString() {
    final sufijo = clave == null ? '' : ', ${clave!.name}';
    return 'AlmacenSeguroException($operacion$sufijo)';
  }
}
