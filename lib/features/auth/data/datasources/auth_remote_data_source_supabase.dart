import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/config_supabase.dart';
import '../../../../core/logging/app_logger.dart';
import '../models/sesion_model.dart';
import 'auth_remote_data_source.dart';

/// Lanza el flujo OAuth por navegador y devuelve `true` si se pudo abrir. Es una costura para
/// los tests: `signInWithOAuth` es una *extensión* de `supabase_flutter` sobre [GoTrueClient]
/// (dispatch estático), así que no se puede mockear como el resto del cliente.
typedef LanzadorOAuth = Future<bool> Function(OAuthProvider proveedor, String redirectTo);

/// [AuthRemoteDataSource] real sobre Supabase Auth (HU-AUTH-003, ADR-016).
///
/// - Email/contraseña: `signInWithPassword` / `signUp` (con nombre, apellido y cédula en
///   `user_metadata`, que es lo que el BFF lee para crear `public.usuario`).
/// - Google: `signInWithOAuth` abre el navegador del sistema; Supabase vuelve a la app por el
///   deep link [ConfigSupabase.redirectOAuth] y `supabase_flutter` (app_links) completa la sesión,
///   que se observa por [GoTrueClient.onAuthStateChange].
/// - La sesión la persiste `supabase_flutter` (hoy en SharedPreferences; pasarla a
///   secure_storage vía `FlutterAuthClientOptions.localStorage` es decisión pendiente, ADR-003).
///
/// Traduce [AuthException] a [AuthRemoteException]; el repositorio las convierte en `Failure`.
/// Nunca loguea email ni tokens (convenciones §7.5).
final class AuthRemoteDataSourceSupabase implements AuthRemoteDataSource {
  AuthRemoteDataSourceSupabase(
    this._auth, {
    this._lanzarOAuth,
    this.esperaOAuth = const Duration(minutes: 2),
    AppLogger? logger,
  }) : _log = logger ?? AppLogger.instance;

  final GoTrueClient _auth;
  final LanzadorOAuth? _lanzarOAuth;
  final AppLogger _log;

  /// Cuánto se espera a que el usuario vuelva del navegador antes de darlo por abandonado.
  final Duration esperaOAuth;

  static const String _mensajeEmailNoConfirmado =
      'Tenés que verificar tu correo antes de entrar. Revisá tu bandeja.';
  static const String _mensajeDemasiadosIntentos =
      'Demasiados intentos. Esperá unos minutos y volvé a probar.';
  static const String _mensajeGoogleNoCompletado =
      'No se completó el ingreso con Google. Probá de nuevo';

  @override
  Future<SesionModel> iniciarSesion({required String email, required String password}) async {
    final respuesta = await _traduciendo(
      () => _auth.signInWithPassword(email: email, password: password),
    );
    final sesion = respuesta.session;
    if (sesion == null) throw const ServidorException(status: 200);
    return _aModelo(sesion);
  }

  @override
  Future<void> solicitarRecuperacionPassword(String email) => _traduciendo(
    () => _auth.resetPasswordForEmail(email, redirectTo: ConfigSupabase.redirectOAuth),
  );

  @override
  Future<SesionModel?> registrar({
    required String nombre,
    required String apellido,
    required String cedula,
    required String email,
    required String password,
  }) async {
    final respuesta = await _traduciendo(
      () => _auth.signUp(
        email: email,
        password: password,
        data: {'nombre': nombre, 'apellido': apellido, 'cedula': cedula},
        // Enlace de verificación → vuelve a la app por el deep link (declarado en el manifest),
        // no al Site URL (localhost:3000 por default). Ver README § Supabase para el dashboard.
        emailRedirectTo: ConfigSupabase.redirectOAuth,
      ),
    );
    final sesion = respuesta.session;
    if (sesion != null) return _aModelo(sesion);

    // Sin sesión: o el email ya existía (con "confirmar email" activo Supabase no lo dice para
    // no filtrar cuentas: devuelve un usuario sin identidades) o falta confirmar el email.
    final identidades = respuesta.user?.identities;
    if (identidades != null && identidades.isEmpty) throw const EmailYaRegistradoException();

    // Verificación de email (HU-AUTH-002): con "Confirm email" activo, signUp no deja sesión
    // iniciada. No es un error — la cuenta se creó, falta que el usuario confirme el correo.
    _log.info(LogModulo.auth, 'REGISTRO_PENDIENTE', 'signUp sin sesión: requiere confirmar email');
    return null;
  }

  @override
  Future<SesionModel> iniciarSesionConGoogle() async {
    // Suscribirse antes de lanzar el navegador: el deep link puede volver muy rápido.
    final completer = Completer<Session>();
    final suscripcion = _auth.onAuthStateChange.listen((estado) {
      final sesion = estado.session;
      // El link de verificación de email usa el mismo redirect que Google (ConfigSupabase.
      // redirectOAuth): un signedIn disparado por confirmar el correo no es un login con Google,
      // así que hay que exigir que el proveedor de la sesión sea efectivamente `google`.
      final esGoogle = sesion?.user.appMetadata['provider'] == 'google';
      if (estado.event == AuthChangeEvent.signedIn &&
          sesion != null &&
          esGoogle &&
          !completer.isCompleted) {
        completer.complete(sesion);
      }
    });

    try {
      final lanzar = _lanzarOAuth ?? _lanzarOAuthReal;
      final abierto = await _traduciendo(
        () => lanzar(OAuthProvider.google, ConfigSupabase.redirectOAuth),
      );
      if (!abierto) {
        _log.warn(LogModulo.auth, 'OAUTH_SIN_NAVEGADOR', 'no se pudo abrir el navegador');
        throw const ServidorException(mensaje: _mensajeGoogleNoCompletado);
      }

      final sesion = await completer.future.timeout(esperaOAuth);
      return _aModelo(sesion);
    } on TimeoutException {
      _log.warn(LogModulo.auth, 'OAUTH_TIMEOUT', 'el usuario no volvió del navegador', {
        'segundos': esperaOAuth.inSeconds,
      });
      throw const ServidorException(mensaje: _mensajeGoogleNoCompletado);
    } finally {
      await suscripcion.cancel();
    }
  }

  Future<bool> _lanzarOAuthReal(OAuthProvider proveedor, String redirectTo) =>
      _auth.signInWithOAuth(
        proveedor,
        redirectTo: redirectTo,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

  @override
  Future<SesionModel?> obtenerSesionActual() async {
    final actual = _auth.currentSession;
    if (actual == null) return null;
    if (!actual.isExpired) return _aModelo(actual);

    final refrescada = await _traduciendo(() => _auth.refreshSession());
    final sesion = refrescada.session;
    return sesion == null ? null : _aModelo(sesion);
  }

  @override
  Future<void> cerrarSesion(String accessToken) => _traduciendo(() => _auth.signOut());

  @override
  Future<void> reenviarVerificacion(String email) => _traduciendo(
    () => _auth.resend(
      email: email,
      type: OtpType.signup,
      emailRedirectTo: ConfigSupabase.redirectOAuth,
    ),
  );

  @override
  Stream<void> get erroresVerificacionEmail => _auth.onAuthStateChange.transform(
    StreamTransformer<AuthState, void>.fromHandlers(
      handleData: (_, _) {},
      // `getSessionFromUrl` (dentro de supabase_flutter) traduce el error del deep link a un
      // `AuthException` y lo empuja acá como error del stream (`notifyException`), en vez de un
      // evento normal. `statusCode` es, pese al nombre, el `error_code` crudo de la URL —
      // `otp_expired` es el único que Supabase usa para "vencido o ya usado" en un link de
      // verificación. Cualquier otro error del stream (p. ej. un signInWithOAuth cancelado) se
      // descarta acá: no es de esta pantalla.
      handleError: (error, stackTrace, sink) {
        if (error is AuthException && error.statusCode == 'otp_expired') sink.add(null);
      },
    ),
  );

  static SesionModel _aModelo(Session sesion) {
    final expiraEnSegundos = sesion.expiresAt;
    final expiraEn = expiraEnSegundos != null
        ? DateTime.fromMillisecondsSinceEpoch(expiraEnSegundos * 1000, isUtc: true)
        : DateTime.now().toUtc().add(Duration(seconds: sesion.expiresIn ?? 3600));
    return SesionModel(
      usuarioId: sesion.user.id,
      email: sesion.user.email ?? '',
      accessToken: sesion.accessToken,
      expiraEn: expiraEn,
    );
  }

  /// Ejecuta [accion] y traduce toda [AuthException] a la [AuthRemoteException] equivalente.
  /// Cualquier otra excepción sube tal cual (el repositorio la convierte en `FailureInesperado`).
  Future<T> _traduciendo<T>(Future<T> Function() accion) async {
    try {
      return await accion();
    } on AuthException catch (e) {
      throw _traducir(e);
    }
  }

  AuthRemoteException _traducir(AuthException e) {
    if (e is AuthRetryableFetchException) return const SinConexionException();

    final status = int.tryParse(e.statusCode ?? '');
    final mensaje = e.message.toLowerCase();
    // Estos strings son los error codes que devuelve el servidor de Supabase Auth (lista oficial
    // en su documentación), no el enum `ErrorCode` de gotrue-dart — el cliente no los tipa a
    // todos, así que se comparan por `code` crudo. El fallback por status+texto de abajo cubre
    // los GoTrue viejos que ni siquiera mandan `code`.
    switch (e.code) {
      case 'invalid_credentials':
        return const CredencialesInvalidasException();
      case 'user_already_exists' || 'email_exists':
        return const EmailYaRegistradoException();
      case 'email_not_confirmed':
        _log.warn(LogModulo.auth, 'EMAIL_NO_CONFIRMADO', 'login con email sin confirmar');
        return ServidorException(status: status, mensaje: _mensajeEmailNoConfirmado);
      case 'weak_password':
        return const PasswordDebilException();
      case 'over_email_send_rate_limit' || 'over_request_rate_limit':
        _log.warn(LogModulo.auth, 'RATE_LIMIT', 'límite de intentos/emails de Supabase alcanzado');
        return ServidorException(status: status, mensaje: _mensajeDemasiadosIntentos);
    }

    // Versiones de GoTrue sin `error_code`: se cae al texto, que es estable desde hace años.
    if (status == 400 && mensaje.contains('invalid login credentials')) {
      return const CredencialesInvalidasException();
    }
    if (status == 422 && mensaje.contains('already registered')) {
      return const EmailYaRegistradoException();
    }
    // El free tier de Supabase sin SMTP propio manda como máximo ~2 emails por hora: sin `code`
    // (Edge Functions / gateways viejos) el 429 es la única pista.
    if (status == 429) {
      return ServidorException(status: status, mensaje: _mensajeDemasiadosIntentos);
    }

    // `signup_disabled`, `validation_failed`, `bad_json` u otro código sin caso propio: no hay
    // texto lindo para inventar, pero tampoco se puede mandar `e.message` de Supabase tal cual a
    // la UI — no está garantizado que no lleve datos del usuario (convención §7.5, "ningún
    // Failure lleva PII"). Se muestra solo el código, que sí es seguro.
    _log.warn(LogModulo.auth, 'AUTH_ERROR', 'error de Supabase Auth sin traducción', {
      'status': status,
      'code': e.code,
    });
    return ServidorException(
      status: status,
      mensaje: 'No se pudo completar la operación (${e.code ?? 'desconocido'}).',
    );
  }
}
