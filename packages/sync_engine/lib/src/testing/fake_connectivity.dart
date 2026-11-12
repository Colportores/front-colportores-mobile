import 'dart:async';

import '../core/ports.dart';

/// Conectividad controlada por el test.
///
/// Es la mitad del trigger de §5.2: `goOnline()` es lo que en el dispositivo
/// dispara un ciclo de sync al recuperar la red. Sin este fake, probar ese
/// trigger obligaría a poner un celular en modo avión a mano.
///
/// Distingue Wi-Fi de datos móviles (HU-SYNC-008): `goOnline()` y `goWifi()`
/// conectan por Wi-Fi, `goMobile()` por datos móviles.
class FakeConnectivityPort implements ConnectivityPort {
  FakeConnectivityPort({bool online = true, bool wifi = true})
    : _online = online,
      _wifi = online && wifi;

  final _control = StreamController<bool>.broadcast();
  final _controlWifi = StreamController<bool>.broadcast();
  bool _online;
  bool _wifi;

  @override
  Stream<bool> get onlineChanges => _control.stream;

  @override
  Future<bool> get isOnline async => _online;

  @override
  Future<bool> get isOnWifi async => _wifi;

  @override
  Stream<bool> get wifiChanges => _controlWifi.stream;

  /// Vuelve la red, por Wi-Fi.
  void goOnline() => goWifi();

  void goOffline() => _set(online: false, wifi: false);

  /// Hay red, pero es de datos móviles.
  void goMobile() => _set(online: true, wifi: false);

  /// Hay red, y es Wi-Fi.
  void goWifi() => _set(online: true, wifi: true);

  void _set({required bool online, required bool wifi}) {
    final cambioOnline = _online != online;
    final cambioWifi = _wifi != wifi;
    _online = online;
    _wifi = wifi;
    if (cambioOnline) _control.add(online);
    if (cambioWifi) _controlWifi.add(wifi);
  }

  Future<void> dispose() async {
    await _control.close();
    await _controlWifi.close();
  }
}
