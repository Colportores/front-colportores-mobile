import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/config_supabase.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/motivo_expiracion.dart';
import '../../domain/entities/politica_sesion.dart';
import '../models/sesion_model.dart';
import 'almacen_sesion_supabase.dart';
import 'auth_remote_data_source.dart';
import 'emision_jwt.dart';

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
/// - Verificación de email (HU-AUTH-002, issue #84): el enlace del correo vuelve por
///   [ConfigSupabase.redirectVerificacionEmail] (mismo deep link, path propio `/verificado`);
///   [verificacionesExitosas] cruza ese path (visto con una suscripción propia a `app_links`, en
///   paralelo a la que arma `supabase_flutter` por su cuenta — el plugin soporta varios
///   suscriptores) contra el próximo `signedIn` para distinguirlo de un login/registro normal.
/// - La sesión la persiste `supabase_flutter` en el almacén seguro ([AlmacenSesionSupabase], que
///   `main.dart` le pasa como `FlutterAuthClientOptions.localStorage`) y la renueva sola
///   (`autoRefreshToken`): es el único mecanismo de refresh de la app (HU-AUTH-007).
///
/// Traduce [AuthException] a [AuthRemoteException]; el repositorio las convierte en `Failure`.
/// Nunca loguea email ni tokens (convenciones §7.5).
final class AuthRemoteDataSourceSupabase implements AuthRemoteDataSource {
  AuthRemoteDataSourceSupabase(
    this._auth, {
    this._lanzarOAuth,
    this.esperaOAuth = const Duration(minutes: 2),
    Stream<Uri>? enlacesEntrantes,
    this._sesionPersistida,
    AppLogger? logger,
  }) : _enlacesEntrantes = enlacesEntrantes ?? AppLinks().uriLinkStream,
       _log = logger ?? AppLogger.instance {
    _verificacionExitosaController = StreamController<void>.broadcast(
      onListen: _empezarAEscucharVerificacionExitosa,
      onCancel: _dejarDeEscucharVerificacionExitosa,
    );
  }

  final GoTrueClient _auth;
  final AlmacenSesionSupabase? _sesionPersistida;
  final LanzadorOAuth? _lanzarOAuth;
  final AppLogger _log;

  /// Cuánto se espera a que el usuario vuelva del navegador antes de darlo por abandonado.
  final Duration esperaOAuth;

  /// Deep links entrantes (`AppLinks().uriLinkStream` por default; costura para los tests, mismo
  /// motivo que [LanzadorOAuth]). Incluye el enlace inicial si la app arrancó desde uno (arranque
  /// en frío) y los que lleguen mientras corre.
  final Stream<Uri> _enlacesEntrantes;

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
        // no al Site URL (localhost:3000 por default). Path propio `/verificado` (issue #84) para
        // poder distinguir, del lado de la app, esta confirmación de un login/registro normal.
        // Ver README § Supabase para el dashboard.
        emailRedirectTo: ConfigSupabase.redirectVerificacionEmail,
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

  // Sin refrescar: `Supabase.initialize` ya cargó la sesión guardada (aunque su JWT de acceso haya
  // vencido) y `autoRefreshToken` la renueva en cuanto hay red. Refrescar acá frenaría el arranque
  // sin red con los reintentos de gotrue y dejaría al usuario afuera (HU-AUTH-007, "Refresh
  // offline con JWT vigente").
  @override
  Future<SesionModel?> obtenerSesionActual() async => sesionEnElCliente();

  // gotrue comparte un solo refresh entre las llamadas simultáneas con el mismo refresh token
  // (`_pendingRefreshes`), y es el mismo que usa `autoRefreshToken`: no hay dos mecanismos.
  // Cualquier rechazo que no sea de red hace que gotrue suelte la sesión (y emita `signedOut` con
  // `sessionExpired`, que llega a [expiraciones]).
  @override
  Future<SesionModel> renovarSesion() async {
    try {
      final sesion = (await _auth.refreshSession()).session;
      if (sesion == null) throw const SesionRevocadaException();
      return _aModelo(sesion);
    } on AuthRetryableFetchException {
      throw const SinConexionException();
    } on AuthException catch (e) {
      _log.warn(LogModulo.auth, 'REFRESH_RECHAZADO', 'el servidor rechazó el refresh', {
        'status': e.statusCode,
        'code': e.code,
      });
      throw const SesionRevocadaException();
    }
  }

  @override
  late final Stream<MotivoExpiracion> expiraciones = _crearExpiraciones();

  Stream<MotivoExpiracion> _crearExpiraciones() {
    late final StreamController<MotivoExpiracion> controller;
    StreamSubscription<AuthState>? delCliente;
    StreamSubscription<void>? delAlmacen;
    controller = StreamController<MotivoExpiracion>.broadcast(
      onListen: () {
        delCliente = _auth.onAuthStateChange.listen(
          (estado) {
            if (estado.event == AuthChangeEvent.signedOut &&
                estado.signOutReason == SignOutReason.sessionExpired) {
              controller.add(MotivoExpiracion.revocada);
            }
          },
          // Los errores del stream son de otros flujos (deep links); acá no se usan.
          onError: (Object _, StackTrace _) {},
        );
        delAlmacen = _sesionPersistida?.vencimientos.listen(
          (_) => controller.add(MotivoExpiracion.inactividad),
        );
      },
      onCancel: () {
        unawaited(delCliente?.cancel());
        unawaited(delAlmacen?.cancel());
      },
    );
    return controller.stream;
  }

  @override
  bool tomarVencimientoPorInactividad() => _sesionPersistida?.tomarVencimiento() ?? false;

  @override
  SesionModel? sesionEnElCliente() {
    final actual = _auth.currentSession;
    return actual == null ? null : _aModelo(actual);
  }

  // Siempre `signOut`, aunque [accessToken] no coincida con el del cliente (`autoRefreshToken`
  // lo renueva): es lo único que borra la sesión que persiste `supabase_flutter`, que si no se
  // restauraría al rearrancar sin pedir contraseña. `signOut` la suelta **antes** de llamar al
  // servidor (gotrue 2.27), así que sin red la copia local ya no está cuando lanza.
  @override
  Future<void> cerrarSesion(String accessToken) => _traduciendo(() => _auth.signOut());

  // `admin.signOut` es el mismo `POST /logout` que usa `signOut` por dentro, pero con el token
  // explícito. Su scope por defecto es **global** (cerraría también la sesión nueva y las de otros
  // equipos): acá va `local`.
  @override
  Future<void> revocarSesion(String accessToken) =>
      _traduciendo(() => _auth.admin.signOut(accessToken, scope: SignOutScope.local));

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

  late final StreamController<void> _verificacionExitosaController;
  StreamSubscription<Uri>? _suscripcionEnlaces;
  StreamSubscription<AuthState>? _suscripcionAuthParaVerificacion;

  /// `true` desde que llega un deep link a `/verificado` hasta el próximo `signedIn` (o hasta que
  /// se cancela la escucha). Es lo que distingue, del lado de la app, ese `signedIn` de uno de
  /// login/registro normal — Supabase no los separa por `AuthChangeEvent`.
  bool _esperandoConfirmacionEmail = false;

  @override
  Stream<void> get verificacionesExitosas => _verificacionExitosaController.stream;

  // Suscripción perezosa (recién al primer `listen`, igual que hace un StreamProvider `keepAlive`
  // de la app real): así un test que solo ejercita otro método de esta clase no dispara
  // `AppLinks()` (canal de plataforma) sin necesidad.
  void _empezarAEscucharVerificacionExitosa() {
    _esperandoConfirmacionEmail = false;
    _suscripcionEnlaces = _enlacesEntrantes.listen((uri) {
      if (uri.path == '/verificado') _esperandoConfirmacionEmail = true;
    });
    _suscripcionAuthParaVerificacion = _auth.onAuthStateChange.listen(
      (estado) {
        if (!_esperandoConfirmacionEmail) return;
        if (estado.event == AuthChangeEvent.signedIn && estado.session != null) {
          _esperandoConfirmacionEmail = false;
          _verificacionExitosaController.add(null);
        }
      },
      // Los errores del stream (p. ej. `otp_expired`) son cosa de `erroresVerificacionEmail`;
      // acá no hay nada que hacer con ellos, pero sin `onError` un error no manejado se propaga
      // como excepción no capturada de la zona (rompe el test/la app igual).
      onError: (Object _, StackTrace _) {},
    );
  }

  void _dejarDeEscucharVerificacionExitosa() {
    unawaited(_suscripcionEnlaces?.cancel());
    unawaited(_suscripcionAuthParaVerificacion?.cancel());
    _suscripcionEnlaces = null;
    _suscripcionAuthParaVerificacion = null;
  }

  /// La ventana de 30 días arranca cuando el servidor emitió el JWT (su `iat`, con el reloj del
  /// servidor): es la última actividad de red de la sesión (HU-AUTH-007).
  static SesionModel _aModelo(Session sesion) => SesionModel(
    usuarioId: sesion.user.id,
    email: sesion.user.email ?? '',
    accessToken: sesion.accessToken,
    expiraEn: PoliticaSesion.expiraEn(emisionDelJwt(sesion.accessToken) ?? DateTime.now()),
  );

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
