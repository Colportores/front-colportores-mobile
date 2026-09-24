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

  /// Deep link propio para la verificación de email (HU-AUTH-002, decisión de Cristian del
  /// 23/09, issue #84). Mismo scheme y host que [redirectOAuth] — el intent-filter de
  /// `AndroidManifest.xml` no filtra por path, así que lo captura igual — pero un path propio
  /// (`/verificado`) para que la app pueda distinguir, del lado del cliente, un `signedIn` que
  /// vino de confirmar el correo de uno de un login/registro normal (Supabase no los separa por
  /// `AuthChangeEvent`).
  ///
  /// **Pendiente de backend** (no se puede hacer desde la app, ver issue #84): sumar esta URL —o
  /// un comodín `io.supabase.colportores://login-callback/**`— en el dashboard de Supabase,
  /// Authentication → URL Configuration → Redirect URLs. Sin eso, Supabase rechaza el
  /// `emailRedirectTo` y el enlace de verificación no vuelve a la app.
  static const String redirectVerificacionEmail =
      'io.supabase.colportores://login-callback/verificado';
}
