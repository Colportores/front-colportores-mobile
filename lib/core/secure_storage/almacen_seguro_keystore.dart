import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'almacen_seguro.dart';

/// [AlmacenSeguro] sobre `flutter_secure_storage` (ADR-007): Android Keystore e iOS Keychain.
///
/// Es el **único** archivo del proyecto que conoce el plugin — misma regla que el anillo de
/// adaptadores del contrato de sync (R-A1). Traduce toda `Exception` de la plataforma a
/// [AlmacenSeguroException] para que el puerto tenga un solo modo de falla.
///
/// ## Opciones de plataforma
///
/// Se usan **las que trae el plugin**, y se pueden inyectar por constructor. Tres de ellas son
/// decisiones de seguridad todavía abiertas, y se resuelven en HU-AUTH-009 (#27) antes de que la
/// app guarde una sal real:
///
/// - `AndroidOptions.resetOnError` viene en `true`: ante un error del Keystore el plugin **borra
///   los datos de forma permanente**. Aplicado a la sal eso convierte un fallo transitorio en la
///   pérdida definitiva de la DB local, mientras que HU-AUTH-009 pide reportar el error al
///   usuario. Hay que decidirlo (Supuesto S10) — acá no se elige por nadie.
/// - `AndroidOptions.encryptedSharedPreferences` viene en `false`. HU-AUTH-009 lo nombra como el
///   almacenamiento alternativo para dispositivos sin Keystore de hardware, pero solo después de
///   que el usuario dé consentimiento explícito — o sea que prenderlo de entrada se saltearía el
///   consentimiento. Mismo Supuesto S10.
/// - `IOSOptions.accessibility` viene en `unlocked` (`kSecAttrAccessibleWhenUnlocked`): la sal no
///   se puede leer con el dispositivo bloqueado. El backup nocturno y el sync en background
///   (ADR-003, ADR-017) sí corren con el equipo bloqueado, así que el nivel de accesibilidad se
///   define cuando se diseñe ese flujo.
///
/// `synchronizable` sí queda en `false` (el default del plugin) y no hay motivo para moverlo: la
/// sal **debe ser distinta por dispositivo** (HU-AUTH-009), o sea que no puede sincronizar por
/// iCloud Keychain.
///
/// Los cuatro valores de arriba los fija un test contra [opcionesAndroid] y [opcionesIos]: quien
/// resuelva S10 tiene que actualizar esta doc junto con el código, no puede cambiar uno solo.
///
/// ## Android: Auto Backup deshabilitado
///
/// En Android el plugin guarda el ciphertext en SharedPreferences y la clave que lo envuelve en
/// el Keystore. Auto Backup respalda lo primero y no lo segundo, así que tras un restore en otro
/// equipo `read` falla y —con `resetOnError` en `true`— devuelve `null` como si la sal nunca
/// hubiera existido. Por eso el manifest lleva `android:allowBackup="false"` y
/// `android:dataExtractionRules` (README del plugin, "Disabling Auto Backup"); no quitarlos.
final class AlmacenSeguroKeystore implements AlmacenSeguro {
  AlmacenSeguroKeystore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

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
