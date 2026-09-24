/// Configuración de Supabase (ADR-016: la app se autentica contra Supabase Auth y el BFF valida
/// el JWT). Los valores entran en compilación por `--dart-define` (README § Desarrollo), nunca
/// hardcodeados ni versionados: la anon key es pública pero cambia por entorno.
///
/// Si falta alguno de los dos, [configurada] es `false` y la app corre con los fakes en memoria
/// (tests, CI sin variables, demo sin backend) — exactamente igual que antes de #22.
abstract final class ConfigSupabase {
  static const String url = String.fromEnvironment('SUPABASE_URL');

  /// Anon key legacy (JWT) o publishable key nueva (`sb_publishable_…`): Supabase acepta las dos.
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get configurada => url.isNotEmpty && anonKey.isNotEmpty;

  /// Deep link al que Supabase redirige al terminar el OAuth por navegador (Google). Tiene que
  /// estar (a) en `AndroidManifest.xml` como intent-filter de `MainActivity` y (b) en el
  /// dashboard: Authentication → URL Configuration → Redirect URLs.
  static const String redirectOAuth = 'io.supabase.colportores://login-callback/';

  /// Deep link del enlace de recuperación de contraseña (HU-AUTH-004 lo pide, HU-AUTH-005 lo
  /// recibe). Mismo scheme y host que [redirectOAuth] (el mismo intent-filter lo captura), con una
  /// ruta propia para distinguirlo de la verificación de email: Supabase manda el mismo error para
  /// los dos cuando el enlace venció (`RegistroEnlacesAuth`). **También tiene que estar** en el
  /// dashboard: Authentication → URL Configuration → Redirect URLs.
  static const String redirectRecuperacion =
      'io.supabase.colportores://login-callback/recuperacion';
}
