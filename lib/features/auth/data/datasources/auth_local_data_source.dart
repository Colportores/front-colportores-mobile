import '../models/sesion_model.dart';

/// Copia de la sesión que usa la app mientras corre ([AuthLocalDataSourceEnMemoria] en
/// `main.dart`). Lo que sobrevive a un reinicio es la sesión del proveedor, que `supabase_flutter`
/// guarda en el almacén seguro (`AlmacenSesionSupabase`, HU-AUTH-007).
///
/// El JWT nunca va a SharedPreferences ni a la DB: solo a Keystore/Keychain.
abstract interface class AuthLocalDataSource {
  Future<SesionModel?> leerSesion();

  Future<void> guardarSesion(SesionModel sesion);

  Future<void> borrarSesion();
}
