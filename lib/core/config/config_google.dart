/// Configuración de Google para autorizar el respaldo en Drive (HU-SYNC-004). Los identificadores
/// de cliente no son secretos pero cambian por entorno: entran en compilación por `--dart-define`
/// (README § Desarrollo, `docs/google-drive-oauth.md`) y no se versionan.
///
/// Si falta [serverClientId], [configurada] es `false`: el respaldo no se puede conectar (la
/// persona ve «No pudimos conectar tu Drive») y la app corre igual, como con Supabase sin
/// configurar.
abstract final class ConfigGoogle {
  /// ID de cliente de tipo «Aplicación web» del proyecto de Google Cloud: lo pide `google_sign_in`
  /// en Android (`serverClientId`). Hay que registrar además un cliente Android por huella de
  /// firma (`docs/google-drive-oauth.md`, paso 5).
  static const String serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// ID de cliente de iOS. Va también en `ios/Runner/Info.plist` (`GIDClientID` y el esquema URL
  /// invertido, riesgo R29).
  static const String iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  static bool get configurada => serverClientId.isNotEmpty;

  /// El permiso de Drive que se pide: la carpeta oculta de la app y nada más del Drive de la
  /// persona (ADR-006, HU-SYNC-004).
  static const String alcanceDrive = 'https://www.googleapis.com/auth/drive.appdata';
}
