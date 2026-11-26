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
///
/// **Enlace con código de un solo uso** (`?token_hash=<código>&type=recovery`, la plantilla del
/// correo de recuperación desde backend-supabase#313): `supabase_flutter` no lo reconoce (solo
/// canjea `code`, `access_token` o un error), así que el predicado lo registra, **no** lo deja
/// pasar a `supabase_flutter` (devuelve `false`) y le entrega el código a quien lo canjea con
/// `verifyOTP` ([recibirCodigos]). El enlace viejo con `?code=` sigue por el camino de siempre.
final class RegistroEnlacesAuth {
  RegistroEnlacesAuth({DateTime Function()? ahora}) : _ahora = ahora ?? DateTime.now;

  final DateTime Function() _ahora;

  /// Mientras el mismo código llegue de nuevo antes de este plazo, es el mismo toque entregado
  /// dos veces (arranque en frío más `onNewIntent`), no un segundo enlace: canjearlo otra vez
  /// mostraría «enlace vencido» encima de la pantalla de la contraseña nueva.
  static const Duration plazoDeUnMismoToque = Duration(seconds: 10);

  /// La que usa la app (la engancha `main.dart`).
  static final RegistroEnlacesAuth instancia = RegistroEnlacesAuth();

  Uri? _ultimo;
  bool _recuperacionEnCanje = false;

  void Function(String codigo)? _receptor;
  String? _codigoSinTomar;
  String? _ultimoCodigo;
  DateTime? _ultimoCodigoEn;

  /// Si el último deep link que llegó es de recuperación de contraseña.
  bool get ultimoEsRecuperacion => _ultimo != null && _esRecuperacion(_ultimo!);

  /// Predicado para `detectSessionInUriPredicate`: registra [uri] y decide si es un callback de
  /// auth con la misma heurística que `supabase_flutter` usa por defecto (algún parámetro de auth en
  /// la query o en el fragmento).
  bool esCallbackDeAuth(Uri uri) {
    _ultimo = uri;
    if (_esRecuperacionConCodigo(uri)) {
      _recibirCodigo(uri.queryParameters['token_hash']!);
      return false;
    }
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

  /// Engancha a quien canjea los códigos de recuperación ([receptor], uno solo): le entrega ya el
  /// que llegó antes de que existiera (un enlace de arranque en frío llega antes que la UI; si
  /// llegaron varios, solo el último, porque cada pedido nuevo anula al anterior) y después cada
  /// uno que llegue. Devuelve lo que lo desengancha.
  void Function() recibirCodigos(void Function(String codigo) receptor) {
    _receptor = receptor;
    final guardado = _codigoSinTomar;
    _codigoSinTomar = null;
    if (guardado != null) receptor(guardado);
    return () {
      if (identical(_receptor, receptor)) _receptor = null;
    };
  }

  void _recibirCodigo(String codigo) {
    final ahora = _ahora();
    final repetido =
        codigo == _ultimoCodigo &&
        _ultimoCodigoEn != null &&
        ahora.difference(_ultimoCodigoEn!) < plazoDeUnMismoToque;
    if (repetido) return;
    _ultimoCodigo = codigo;
    _ultimoCodigoEn = ahora;
    _recuperacionEnCanje = true;
    final receptor = _receptor;
    if (receptor == null) {
      _codigoSinTomar = codigo;
    } else {
      receptor(codigo);
    }
  }

  static bool _esRecuperacionConCodigo(Uri uri) =>
      _esRecuperacion(uri) &&
      uri.queryParameters['type'] == 'recovery' &&
      uri.queryParameters.containsKey('token_hash');

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
