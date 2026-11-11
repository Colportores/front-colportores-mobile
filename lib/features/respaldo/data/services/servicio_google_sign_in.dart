import 'package:google_sign_in/google_sign_in.dart';

import '../../../../core/config/config_google.dart';
import 'servicio_google.dart';
import 'verificador_alcance_google.dart';

/// [ServicioGoogle] sobre `google_sign_in` 7.x. Es la única pieza que toca el plugin: no se prueba
/// en la VM (hace falta Google Play Services o iOS), así que no lleva lógica; lo que decide qué
/// hacer con cada fallo es el repositorio, que sí está probado.
///
/// `google_sign_in` 7 no entrega el refresh token: el token de acceso (una hora) se vuelve a pedir
/// en silencio con `authorizationForScopes`, que no abre ninguna pantalla y devuelve `null` cuando
/// la persona ya no tiene dado el permiso.
class ServicioGoogleSignIn implements ServicioGoogle {
  ServicioGoogleSignIn({GoogleSignIn? google, VerificadorAlcanceGoogle? verificador})
    : _google = google ?? GoogleSignIn.instance,
      _verificador = verificador ?? VerificadorAlcanceGoogle();

  final GoogleSignIn _google;
  final VerificadorAlcanceGoogle _verificador;

  static const _alcances = [ConfigGoogle.alcanceDrive];

  Future<void>? _inicializacion;

  /// `initialize` se llama una sola vez por proceso. Si falla, se vuelve a intentar en la próxima.
  Future<void> _inicializar() {
    return _inicializacion ??= _google
        .initialize(
          clientId: ConfigGoogle.iosClientId.isEmpty ? null : ConfigGoogle.iosClientId,
          serverClientId: ConfigGoogle.serverClientId.isEmpty ? null : ConfigGoogle.serverClientId,
        )
        .onError<Object>((error, rastro) {
          _inicializacion = null;
          Error.throwWithStackTrace(error, rastro);
        });
  }

  @override
  Future<CuentaGoogle> conectar() async {
    await _inicializar();
    final cuenta = await _google.authenticate(scopeHint: _alcances);
    final autorizacion = await cuenta.authorizationClient.authorizeScopes(_alcances);
    final concedido = await _verificador.incluye(
      autorizacion.accessToken,
      ConfigGoogle.alcanceDrive,
    );
    if (!concedido) throw const PermisoDriveNoConcedido();
    return CuentaGoogle(id: cuenta.id, email: cuenta.email);
  }

  @override
  Future<String?> tokenSilencioso() async {
    await _inicializar();
    final autorizacion = await _google.authorizationClient.authorizationForScopes(_alcances);
    return autorizacion?.accessToken;
  }

  @override
  Future<void> desconectar() async {
    await _inicializar();
    await _google.disconnect();
  }
}
