/// Inventario de secretos que la app guarda en el almacén seguro del dispositivo.
///
/// El enum es cerrado a propósito: agregar un secreto obliga a declararlo acá, así el inventario
/// completo de lo que la app guarda en Keystore/Keychain se lee de un solo lugar.
///
/// El [id] es el nombre real con el que el secreto queda escrito en el dispositivo. **Cambiarlo
/// deja huérfano lo ya guardado** en los equipos que lo tienen: para la sal eso significa una DB
/// local que ya no se puede abrir.
enum ClaveSegura {
  /// Sal aleatoria de 256 bits con la que se deriva la clave de la DB local
  /// ([ADR-003], R-AU03). No es la clave: es el ingrediente público de la derivación.
  salDb('db_salt'),

  /// Marca de que la DB local ya se creó y migró en este dispositivo (HU-AUTH-009).
  dbInicializada('db_initialized'),

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
/// Es el **único** lugar donde la app guarda material secreto, y todo lo que guarda está
/// inventariado en [ClaveSegura]: hoy la sal con la que se deriva la clave de la DB y la marca de
/// inicialización; la sesión de auth (el JWT) también va a vivir acá cuando `AuthLocalDataSource`
/// tenga implementación real. Lo que **nunca** guarda es la clave de la DB: se deriva de la sal y
/// no toca el disco (ADR-003).
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

  /// Borra **todo** lo que este almacén custodia para la app —cada [ClaveSegura], no solo la sal:
  /// también la marca de inicialización y, cuando esté, la sesión de auth— (HU-AUTH-010, derecho
  /// al borrado). Para borrar un solo secreto está [borrar].
  Future<void> borrarTodo();
}

/// Falla del almacén seguro del dispositivo: Keystore/Keychain ausente, bloqueado o roto.
///
/// No distingue todavía entre "este dispositivo no tiene almacenamiento seguro robusto" y "falló
/// una escritura puntual". Esa clasificación —y qué hace la app con cada una— es el Supuesto S10,
/// que se cierra en HU-AUTH-009 junto con el flujo de consentimiento explícito.
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
