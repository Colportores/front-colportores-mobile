import 'dart:async';

import '../core/ports.dart';

/// Conectividad controlada por el test.
///
/// Es la mitad del trigger de §5.2: `goOnline()` es lo que en el dispositivo
/// dispara un ciclo de sync al recuperar la red. Sin este fake, probar ese
/// trigger obligaría a poner un celular en modo avión a mano.
class FakeConnectivityPort implements ConnectivityPort {
  FakeConnectivityPort({bool online = true}) : _online = online;

  final _control = StreamController<bool>.broadcast();
  bool _online;

  @override
  Stream<bool> get onlineChanges => _control.stream;

  @override
  Future<bool> get isOnline async => _online;

  void goOnline() => _set(true);
  void goOffline() => _set(false);

  void _set(bool valor) {
    if (_online == valor) return;
    _online = valor;
    _control.add(valor);
  }

  Future<void> dispose() => _control.close();
}
