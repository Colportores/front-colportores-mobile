import '../models/sesion_model.dart';

/// Persistencia local de la sesión. La implementación real usa `flutter_secure_storage`
/// (Sprint 2, wrapper `secure_storage`); hasta entonces, [AuthLocalDataSourceEnMemoria].
///
/// El JWT nunca va a SharedPreferences ni a la DB: solo a Keystore/Keychain.
abstract interface class AuthLocalDataSource {
  Future<SesionModel?> leerSesion();

  Future<void> guardarSesion(SesionModel sesion);

  Future<void> borrarSesion();
}
