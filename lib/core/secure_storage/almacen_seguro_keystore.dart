import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'almacen_seguro.dart';

/// [AlmacenSeguro] sobre `flutter_secure_storage` 10.x (ADR-006): Android Keystore e iOS Keychain.
///
/// Es el **único** archivo del proyecto que conoce el plugin — misma regla que el anillo de
/// adaptadores del contrato de sync (R-A1). Traduce toda `Exception` de la plataforma a
/// [AlmacenSeguroException] para que el puerto tenga un solo modo de falla.
///
/// ## Opciones de plataforma (ADR-006)
///
/// - **Android: `resetOnError: false`.** Con el default (`true`) el plugin borra todo ante un error
///   del Keystore, y sin la DEK la DB local queda imposible de abrir para siempre. Con `false` la
///   falla llega a la app, que decide: con envoltorio por contraseña recupera la DEK y reconstruye
///   el almacén; sin él, pregunta antes de empezar de nuevo. **Nunca se borra sin ese sí.**
/// - **iOS: `accessibility: first_unlock_this_device`** (`kSecAttrAccessibleAfterFirstUnlock…
///   ThisDeviceOnly`). La DEK se lee desde el primer desbloqueo después de prender el equipo,
///   aunque después se bloquee: así andan el backup nocturno y el sync en segundo plano. Con
///   `_ThisDeviceOnly` no viaja en backups de iCloud ni de Finder, ni a otro iPhone.
/// - `synchronizable` queda en `false` (el default): la DEK es **distinta por dispositivo**
///   (HU-AUTH-009), así que no puede sincronizar por iCloud Keychain.
/// - `encryptedSharedPreferences` queda en `false`: está deprecado en la 10.x y ADR-006 lo descarta
///   como almacén alternativo para S10 (los equipos con Keystore por software siguen con este
///   mismo almacén, con consentimiento).
///
/// Los valores de arriba los fija un test contra [opcionesAndroid] y [opcionesIos]: quien los
/// cambie tiene que actualizar esta doc (y ADR-006) junto con el código.
///
/// ## Android: Auto Backup deshabilitado
///
/// En Android el plugin guarda el ciphertext en SharedPreferences y la clave que lo envuelve en
/// el Keystore. Auto Backup respalda lo primero y no lo segundo, así que tras un restore en otro
/// equipo `read` fallaría. Por eso el manifest lleva `android:allowBackup="false"` y
/// `android:dataExtractionRules` (README del plugin, "Disabling Auto Backup"); no quitarlos.
final class AlmacenSeguroKeystore implements AlmacenSeguro {
  AlmacenSeguroKeystore({FlutterSecureStorage? storage}) : _storage = storage ?? _porDefecto;

  static const FlutterSecureStorage _porDefecto = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  final FlutterSecureStorage _storage;

  /// Opciones de Android con las que este adaptador habla con el plugin. Solo para que los tests
  /// verifiquen las que enumera la doc de la clase; producción no las necesita.
  @visibleForTesting
  AndroidOptions get opcionesAndroid => _storage.aOptions;

  /// Opciones de iOS con las que este adaptador habla con el plugin. Mismo uso que
  /// [opcionesAndroid].
  @visibleForTesting
  IOSOptions get opcionesIos => _storage.iOptions;

  @override
  Future<String?> leer(ClaveSegura clave) =>
      _traduciendoFallas('leer', clave, () => _storage.read(key: clave.id));

  @override
  Future<void> escribir(ClaveSegura clave, String valor) =>
      _traduciendoFallas('escribir', clave, () => _storage.write(key: clave.id, value: valor));

  @override
  Future<void> borrar(ClaveSegura clave) =>
      _traduciendoFallas('borrar', clave, () => _storage.delete(key: clave.id));

  @override
  Future<void> borrarTodo() => _traduciendoFallas('borrarTodo', null, _storage.deleteAll);

  /// Corre [accion] y envuelve cualquier `Exception` de la plataforma (`PlatformException`,
  /// `MissingPluginException`, …) en [AlmacenSeguroException]. Los `Error` no se atrapan: son
  /// bugs del programa, no fallas del dispositivo.
  Future<T> _traduciendoFallas<T>(
    String operacion,
    ClaveSegura? clave,
    Future<T> Function() accion,
  ) async {
    try {
      return await accion();
    } on Exception catch (e) {
      throw AlmacenSeguroException(operacion: operacion, clave: clave, causa: e);
    }
  }
}
