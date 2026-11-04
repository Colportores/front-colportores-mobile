import 'dart:async';

import '../push_remotas.dart';

/// [PushRemotas] en memoria.
///
/// **No es código de producción.** Es el default de la app mientras no esté `firebase_messaging` (no
/// recibe nada hasta que alguien llame a [llegaConLaAppAbierta], [seTocaConLaAppEnSegundoPlano] o
/// [abrirLaAppConElToque]) y el de los tests.
final class PushRemotasEnMemoria implements PushRemotas {
  PushRemotasEnMemoria({this._abrioLaApp});

  final _alFrente = StreamController<MensajePush>.broadcast();
  final _toques = StreamController<MensajePush>.broadcast();
  MensajePush? _abrioLaApp;

  /// Cuántas veces se preguntó por el mensaje que abrió la app.
  int consultasDeLaQueAbrioLaApp = 0;

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

  /// Llega un mensaje con la app al frente.
  void llegaConLaAppAbierta(Map<String, Object?> datos) => _alFrente.add(MensajePush(datos));

  /// La persona toca la notificación del sistema con la app en segundo plano.
  void seTocaConLaAppEnSegundoPlano(Map<String, Object?> datos) => _toques.add(MensajePush(datos));

  /// El toque sobre la notificación del sistema abrió la app desde cerrada: queda esperando a quien
  /// la pregunte.
  void abrirLaAppConElToque(Map<String, Object?> datos) => _abrioLaApp = MensajePush(datos);
}
