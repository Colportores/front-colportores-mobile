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
final class AlmacenSeguroKeystore implements AlmacenSeguro {
  AlmacenSeguroKeystore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

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
