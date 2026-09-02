// El ciclo de vida de la app como trigger de sync (§5.2, RF-SY05).
//
// Dos momentos, y los dos importan por razones distintas:
//
//   * **Al pasar a segundo plano** hay que vaciar lo que espera la ventana de
//     coalescencia. Sin esto, una venta anotada justo antes de bloquear el
//     teléfono se queda esperando un trigger que no va a llegar hasta el
//     próximo arranque de la app, que puede ser mañana.
//   * **Al volver** se dispara un ciclo: es la primera oportunidad de subir lo
//     de la jornada anterior y de bajar lo que cargó el coordinador mientras
//     tanto.
//
// Vive en la app y no en `sync_engine` porque `WidgetsBinding` es Flutter, y el
// motor tiene que poder correr en la VM (§5.9).

import 'package:flutter/widgets.dart';
import 'package:sync_engine/sync_engine.dart';

/// Conecta el ciclo de vida de la app con el motor.
///
/// ```dart
/// _ciclo = CicloDeVidaSync(motor)..enchufar();
/// // …
/// _ciclo.desenchufar();
/// ```
class CicloDeVidaSync with WidgetsBindingObserver {
  CicloDeVidaSync(this._motor, {void Function(Object error)? onError})
      : _onError = onError;

  final SyncEngine _motor;

  /// Qué hacer si el ciclo falla. Por defecto, nada: una sync que no salió al
  /// ir a segundo plano no es un error de la app, los jobs siguen en la cola y
  /// suben al próximo trigger.
  final void Function(Object error)? _onError;

  void enchufar() => WidgetsBinding.instance.addObserver(this);
  void desenchufar() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      // `inactive` queda afuera a propósito: llega con cada interrupción
      // pasajera —bajar la cortina de notificaciones, el selector de apps, una
      // llamada entrante— y muchas veces vuelve a `resumed` enseguida. Tratarlo
      // como "se fue a segundo plano" haría un ciclo de sync cada vez que el
      // colportor mira la hora.
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _sinEsperar(_motor.flush());

      case AppLifecycleState.resumed:
        _sinEsperar(_motor.trigger(SyncTrigger.appResumed));

      // `detached` es la app terminando: no hay tiempo para un ciclo de red y
      // el motor puede estar cerrándose. Lo encolado ya está en la base —se
      // escribió en la misma transacción que la fila de negocio (§3)— así que
      // no se pierde nada por no hacer nada acá.
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// El callback del ciclo de vida es síncrono, así que el ciclo se dispara y
  /// no se espera. Lo que **no** puede pasar es que el error quede sin atrapar:
  /// un `Future` que falla sin handler tumba la zona.
  ///
  /// Y ojo con lo que esto garantiza: al ir a segundo plano, el sistema puede
  /// matar la app antes de que el `flush()` termine. Es best-effort a
  /// propósito. La garantía dura es otra y ya está: el job se escribió en la
  /// DB local junto con la venta, así que lo peor que pasa es que suba más
  /// tarde.
  void _sinEsperar(Future<Object?> ciclo) {
    ciclo.catchError((Object e) {
      _onError?.call(e);
      return null;
    });
  }
}
