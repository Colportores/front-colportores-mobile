import 'dart:async';

import '../push_remotas.dart';

/// [PushRemotas] en memoria.
///
/// **No es código de producción.** Es el de los tests y el default de la app cuando Firebase no
/// arranca (no recibe nada hasta que alguien llame a [llegaConLaAppAbierta],
/// [seTocaConLaAppEnSegundoPlano] o [abrirLaAppConElToque]).
final class PushRemotasEnMemoria implements PushRemotas {
  PushRemotasEnMemoria({this._abrioLaApp, this.token});

  final _alFrente = StreamController<MensajePush>.broadcast();
  final _toques = StreamController<MensajePush>.broadcast();
  final _rotaciones = StreamController<String>.broadcast();
  MensajePush? _abrioLaApp;

  /// Cuántas veces se preguntó por el mensaje que abrió la app.
  int consultasDeLaQueAbrioLaApp = 0;

  /// El token de FCM de este teléfono. `null`: todavía no tiene (es el caso de la app sin Firebase).
  String? token;

  /// Si no es `null`, [obtenerToken] lanza esto.
  Object? fallaAlObtenerToken;

  /// Si no es `null`, [obtenerToken] espera a que se complete (la plataforma todavía no contestó).
  Completer<void>? tokenDemorado;

  /// Cuántas veces se pidió el token.
  int consultasDelToken = 0;

  @override
  Stream<MensajePush> get conLaAppAbierta => _alFrente.stream;

  @override
  Stream<MensajePush> get tocadas => _toques.stream;

  @override
  Future<MensajePush?> tomarLaQueAbrioLaApp() async {
    consultasDeLaQueAbrioLaApp++;
    final mensaje = _abrioLaApp;
    _abrioLaApp = null;
    return mensaje;
  }

  @override
  Future<String?> obtenerToken() async {
    consultasDelToken++;
    await tokenDemorado?.future;
    if (fallaAlObtenerToken case final falla?) throw falla;
    return token;
  }

  @override
  Stream<String> get tokenRotado => _rotaciones.stream;

  /// El sistema le da un token nuevo al teléfono: [obtenerToken] pasa a devolverlo y se avisa.
  void rotaElToken(String nuevo) {
    token = nuevo;
    _rotaciones.add(nuevo);
  }

  /// Llega un mensaje con la app al frente.
  void llegaConLaAppAbierta(Map<String, Object?> datos) => _alFrente.add(MensajePush(datos));

  /// La persona toca la notificación del sistema con la app en segundo plano.
  void seTocaConLaAppEnSegundoPlano(Map<String, Object?> datos) => _toques.add(MensajePush(datos));

  /// El toque sobre la notificación del sistema abrió la app desde cerrada: queda esperando a quien
  /// la pregunte.
  void abrirLaAppConElToque(Map<String, Object?> datos) => _abrioLaApp = MensajePush(datos);
}
