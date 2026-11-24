import 'dart:async';

import '../../../../core/logging/app_logger.dart';
import '../repositories/token_push_repository.dart';

/// Cada cuánto, como mucho, se vuelve a registrar el teléfono aunque no haya cambiado nada: «si pasa
/// más de 24 h sin que la app reciba un mensaje, retentar el registro en silencio» (HU-NOT-001). El
/// servidor borra un token que FCM rechaza, y la app no se entera.
const Duration repasoDelRegistro = Duration(hours: 24);

/// Cuánto se espera al sistema por su token, y al servidor por el cierre de sesión: ninguna conexión a
/// medias deja la serie de registros ni el cierre de sesión colgados.
const Duration topeDelToken = Duration(seconds: 20);
const Duration topeDelRetiro = Duration(seconds: 3);

/// Mantiene al día, en el servidor, el token de FCM de este teléfono para la colportora de esta
/// sesión (HU-NOT-001, «Token FCM», #414).
///
/// - [sincronizar] pide el token al sistema (o usa el [token] que ya llegó, el de una rotación) y lo
///   sube. Sin conexión o con el servidor caído no se pierde: queda [hayPendiente] y se vuelve a
///   intentar con [sincronizarSiHaceFalta] (al volver a la app, al volver la señal).
/// - **Una sola subida a la vez**: un pedido que llega mientras otra corre no se pisa ni se pierde;
///   al terminar se hace otra con lo último que llegó (un token rotado dos veces seguidas sube el
///   segundo, no el primero).
/// - [retirar] manda el token vacío antes de cerrar la sesión (con la sesión todavía válida), para que
///   el servidor deje de mandarle al teléfono avisos de una cuenta que ya salió.
/// - Nunca lanza, y nada del token va a los logs.
///
/// Vive lo que dura la sesión: en otra sesión, otra instancia (lo que se subió es de otra cuenta).
final class RegistroTokenPush {
  RegistroTokenPush({
    required this._servidor,
    required this._obtenerToken,
    DateTime Function()? ahora,
    AppLogger? logger,
  }) : _ahora = ahora ?? DateTime.now,
       _log = logger ?? AppLogger.instance;

  final TokenPushRepository _servidor;
  final Future<String?> Function() _obtenerToken;
  final DateTime Function() _ahora;
  final AppLogger _log;

  String? _subido;
  DateTime? _subidoEn;
  var _pendiente = false;
  var _retirando = false;

  Future<void>? _corriendo;
  var _otraVez = false;
  String? _tokenQueLlego;

  /// Hay algo que no se pudo subir (o no se pudo obtener) y falta reintentar.
  bool get hayPendiente => _pendiente;

  /// El último token que el servidor confirmó. Para los tests.
  String? get subido => _subido;

  /// Sube el token ya ([token], si el sistema acaba de dar uno nuevo) y espera a que termine, lo que
  /// haya llegado mientras tanto incluido.
  Future<void> sincronizar({String? token}) {
    if (_retirando) return Future<void>.value();
    if (token != null) _tokenQueLlego = token;
    if (_corriendo != null) {
      _otraVez = true;
      return _corriendo!;
    }
    return _corriendo = _correr().whenComplete(() => _corriendo = null);
  }

  /// Vuelve a subir solo si falta: algo quedó pendiente, nunca se subió o pasaron [repasoDelRegistro].
  Future<void> sincronizarSiHaceFalta() {
    final subidoEn = _subidoEn;
    final falta =
        _pendiente || subidoEn == null || _ahora().difference(subidoEn) >= repasoDelRegistro;
    return falta ? sincronizar() : Future<void>.value();
  }

  Future<void> _correr() async {
    do {
      _otraVez = false;
      final dado = _tokenQueLlego;
      _tokenQueLlego = null;
      await _subir(dado);
    } while (_otraVez && !_retirando);
  }

  Future<void> _subir(String? dado) async {
    final String? token;
    if (dado != null) {
      token = dado;
    } else {
      try {
        token = await _obtenerToken().timeout(topeDelToken);
      } on Object catch (e) {
        _pendiente = true;
        _log.warn(LogModulo.push, 'TOKEN_PUSH_OBTENER', 'el sistema no dio el token de push', {
          'tipo': e.runtimeType.toString(),
        });
        return;
      }
    }
    // Un teléfono sin token todavía (sin Firebase en este build, o aún sin registrarse): no hay nada que
    // subir ni nada que reintentar a la fuerza.
    if (token == null || token.isEmpty) return;
    try {
      await _servidor.registrar(token);
      _subido = token;
      _subidoEn = _ahora();
      _pendiente = false;
    } on TokenPushException catch (e) {
      _pendiente = true;
      _log.warn(LogModulo.push, 'TOKEN_PUSH_SUBIR', 'el servidor no guardó el token de push', {
        'tipo': e.runtimeType.toString(),
        if (e is TokenPushServidorException) 'code': e.codigo,
      });
    } on Object catch (e) {
      _pendiente = true;
      _log.warn(LogModulo.push, 'TOKEN_PUSH_SUBIR', 'no se pudo subir el token de push', {
        'tipo': e.runtimeType.toString(),
      });
    }
  }

  /// Manda el token vacío al servidor, antes de cerrar la sesión. Espera a la subida en curso (una
  /// subida tardía no puede dejar el token puesto después del vacío), tarda como mucho
  /// [topeDelRetiro] y nunca lanza: sin conexión el cierre de sesión sigue igual y el token queda donde
  /// estaba (la próxima cuenta que entre en este teléfono se lo quita a esta, que es lo que hace el
  /// servidor al guardarlo).
  ///
  /// Si la sesión no llegara a cerrarse, [sincronizarSiHaceFalta] lo vuelve a subir.
  Future<void> retirar() async {
    _retirando = true;
    try {
      await (_corriendo ?? Future<void>.value()).timeout(topeDelRetiro);
      await _servidor.registrar(null).timeout(topeDelRetiro);
      _subido = null;
      _subidoEn = null;
    } on Object catch (e) {
      _log.info(LogModulo.push, 'TOKEN_PUSH_RETIRAR', 'no se pudo vaciar el token de push', {
        'tipo': e.runtimeType.toString(),
      });
    } finally {
      // Si la sesión sigue (el cierre falló), el teléfono tiene que volver a registrarse.
      _pendiente = true;
      _retirando = false;
    }
  }
}
