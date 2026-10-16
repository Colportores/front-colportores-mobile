import '../../../../core/config/config_supabase.dart';

/// Registra cada deep link que llega a la app **antes** de que `supabase_flutter` lo procese, para
/// saber de qué flujo es (HU-AUTH-005).
///
/// Hace falta porque Supabase manda el mismo error (`otp_expired`) para un enlace de verificación
/// de email vencido (HU-AUTH-002) y para uno de recuperación de contraseña vencido (HU-AUTH-005),
/// y el error llega por `onAuthStateChange` sin la URL. Lo que sí distingue a los dos es la ruta
/// del deep link: la recuperación vuelve por [ConfigSupabase.redirectRecuperacion].
///
/// Se engancha como `FlutterAuthClientOptions.detectSessionInUriPredicate` en `Supabase.initialize`
/// (`main.dart`): `supabase_flutter` lo llama en forma sincrónica con cada link entrante, antes de
/// canjearlo, así que cuando llega el resultado (el evento o el error) el registro ya sabe de dónde
/// vino. Por eso es una instancia única ([instancia]): tiene que existir antes que los providers.
final class RegistroEnlacesAuth {
  RegistroEnlacesAuth();

  /// La que usa la app (la engancha `main.dart`).
  static final RegistroEnlacesAuth instancia = RegistroEnlacesAuth();

  Uri? _ultimo;
  bool _recuperacionEnCanje = false;

  /// Si el último deep link que llegó es de recuperación de contraseña.
  bool get ultimoEsRecuperacion => _ultimo != null && _esRecuperacion(_ultimo!);

  /// Predicado para `detectSessionInUriPredicate`: registra [uri] y decide si es un callback de
  /// auth con la misma heurística que `supabase_flutter` usa por defecto (algún parámetro de auth en
  /// la query o en el fragmento).
  bool esCallbackDeAuth(Uri uri) {
    _ultimo = uri;
    final esDeAuth = _tieneParametrosDeAuth(uri);
    if (esDeAuth && _esRecuperacion(uri)) _recuperacionEnCanje = true;
    return esDeAuth;
  }

  /// Si hay un enlace de recuperación cuyo resultado todavía nadie tomó, lo marca como tomado y
  /// devuelve `true`. Lo usa quien traduce el resultado del canje (el evento de recuperación o un
  /// error) a un enlace válido o vencido, una sola vez por enlace: un error posterior (por ejemplo,
  /// un refresco de token que falla) no se confunde con el enlace.
  bool tomarRecuperacionEnCanje() {
    final habia = _recuperacionEnCanje;
    _recuperacionEnCanje = false;
    return habia;
  }

  static bool _esRecuperacion(Uri uri) {
    final destino = Uri.parse(ConfigSupabase.redirectRecuperacion);
    return uri.scheme == destino.scheme &&
        uri.host == destino.host &&
        _sinBarraFinal(uri.path) == _sinBarraFinal(destino.path);
  }

  static String _sinBarraFinal(String ruta) =>
      ruta.endsWith('/') ? ruta.substring(0, ruta.length - 1) : ruta;

  static bool _tieneParametrosDeAuth(Uri uri) {
    final fragmento = Uri.splitQueryString(uri.fragment);
    bool tiene(String clave) =>
        uri.queryParameters.containsKey(clave) || fragmento.containsKey(clave);
    return tiene('access_token') ||
        tiene('code') ||
        tiene('error') ||
        tiene('error_code') ||
        tiene('error_description');
  }
}
