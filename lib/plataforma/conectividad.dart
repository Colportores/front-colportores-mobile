// El trigger "volvió la red" de §5.2 (RF-SY05).
//
// Sin esto la sincronización automática no existe: queda solo el botón, y el
// colportor que estuvo toda la mañana sin señal tiene que acordarse de
// apretarlo. `SyncEngine` ya escucha `ConnectivityPort.onlineChanges` y dispara
// un ciclo con cada `true`; lo único que faltaba era quien lo alimente.
//
// Vive en la app y no en `sync_engine` porque `connectivity_plus` es un plugin
// de Flutter, y el motor tiene que poder correr en la VM sin emulador (§5.9).

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sync_engine/sync_engine.dart';

/// [ConnectivityPort] sobre `connectivity_plus`.
///
/// **Dice si hay una interfaz de red levantada, no si hay internet.** Un WiFi de
/// hotel con portal cautivo, o datos móviles con el saldo agotado, se reportan
/// como conectado. Eso está bien para lo que se usa acá: un ciclo que sale y
/// falla es transitorio, los jobs vuelven a `PENDING` y se reintenta al próximo
/// trigger. Lo que **no** hay que hacer es tomar esto como "el push va a
/// funcionar" para decidir algo que no se pueda deshacer.
class ConectividadPlus implements ConnectivityPort {
  ConectividadPlus({Connectivity? connectivity})
      : _conn = connectivity ?? Connectivity();

  final Connectivity _conn;

  @override
  Stream<bool> get onlineChanges => _conn.onConnectivityChanged
      .map(_hayRed)
      // `connectivity_plus` emite ante **cualquier** cambio de interfaces:
      // levantar una VPN sobre el mismo WiFi, o pasar de WiFi a móvil, son
      // eventos distintos que significan lo mismo —seguimos online—. Sin
      // `distinct` cada uno de esos dispararía un ciclo de sync completo por
      // un cambio que no cambió nada.
      .distinct();

  @override
  Future<bool> get isOnline async => _hayRed(await _conn.checkConnectivity());

  /// Si la conexión actual **no** se paga por megabyte, para RF-SY08.
  ///
  /// El motor no lo consulta solo: la app decide y llama a
  /// `engine.setDataSaver()`. Se expone acá porque es el único lugar que sabe
  /// por qué interfaz se está saliendo, y el requisito —"solo Wi-Fi si el
  /// ahorro está activo"— no se puede cumplir sin ese dato.
  Stream<bool> get sinCostoChanges =>
      _conn.onConnectivityChanged.map(_sinCosto).distinct();

  Future<bool> get isSinCosto async => _sinCosto(await _conn.checkConnectivity());

  /// Una lista vacía también es "sin red": en algunas plataformas es lo que
  /// llega en vez de `[none]`, y tratarla como conectada haría que el motor
  /// dispare un ciclo cada vez que se apaga el WiFi.
  static bool _hayRed(List<ConnectivityResult> r) =>
      r.any((c) => c != ConnectivityResult.none);

  /// Ethernet y WiFi no se cobran por dato. `vpn` no dice nada del transporte
  /// de abajo —puede ir sobre datos móviles— así que no cuenta como gratis:
  /// ante la duda, el que paga el plan es el colportor.
  static bool _sinCosto(List<ConnectivityResult> r) => r.any((c) =>
      c == ConnectivityResult.wifi || c == ConnectivityResult.ethernet);
}
