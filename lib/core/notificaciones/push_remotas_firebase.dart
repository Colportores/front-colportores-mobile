import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../logging/app_logger.dart';
import 'push_remotas.dart';

/// [PushRemotas] sobre `firebase_messaging` (HU-NOT-003, ADR-014): el adaptador de producción.
///
/// Solo traduce: cada `RemoteMessage` pasa a un [MensajePush] con su mapa `data` y nada más. El
/// título fijo que manda el servidor (`notification`) no se lee: con la app cerrada o en segundo
/// plano lo dibuja el sistema, y el texto completo lo arma la app con `TextosPushRemota` al recibir
/// el mensaje (decisión de Cristian del 04/11, «Push fondo»). Por eso **no hay handler de fondo**
/// (`onBackgroundMessage`): con la app cerrada la app no corre nada.
///
/// Las tres vías del puerto:
/// - [conLaAppAbierta] ← `FirebaseMessaging.onMessage`;
/// - [tocadas] ← `FirebaseMessaging.onMessageOpenedApp`;
/// - [tomarLaQueAbrioLaApp] ← `getInitialMessage()`, una sola vez por instancia (el plugin puede
///   devolver el mismo mensaje en cada llamada mientras viva el proceso, y la raíz de la app se
///   rearma al recuperar un respaldo: la misma push no se abre dos veces).
final class PushRemotasFirebase implements PushRemotas {
  /// Con las fuentes del plugin inyectadas (los tests pasan las suyas; la app usa [delPlugin]).
  PushRemotasFirebase({
    required Stream<RemoteMessage> alFrente,
    required Stream<RemoteMessage> tocadas,
    required this._laQueAbrioLaApp,
  }) : _alFrente = _deDifusion(alFrente).map(_aMensaje),
       _tocadas = _deDifusion(tocadas).map(_aMensaje);

  /// Sobre el plugin real. Firebase ya tiene que estar inicializado (ver [iniciar]).
  factory PushRemotasFirebase.delPlugin(FirebaseMessaging mensajeria) => PushRemotasFirebase(
    alFrente: FirebaseMessaging.onMessage,
    tocadas: FirebaseMessaging.onMessageOpenedApp,
    laQueAbrioLaApp: mensajeria.getInitialMessage,
  );

  final Stream<MensajePush> _alFrente;
  final Stream<MensajePush> _tocadas;
  final Future<RemoteMessage?> Function() _laQueAbrioLaApp;
  var _yaSeTomo = false;

  /// Inicializa Firebase y devuelve el adaptador, o `null` si este build no tiene Firebase.
  ///
  /// Sin el archivo de configuración de la plataforma (`google-services.json` con el applicationId
  /// de este build, o `GoogleService-Info.plist` en iOS) `Firebase.initializeApp()` falla: la app
  /// arranca igual, sin push remotas (queda el fake que no recibe nada), y lo deja en el log. Es el
  /// caso de `flutter run` en local y de los builds cuyo applicationId todavía no está registrado
  /// en el proyecto de Firebase.
  static Future<PushRemotas?> iniciar({
    Future<void> Function()? inicializar,
    PushRemotas Function()? crear,
  }) async {
    try {
      await (inicializar ?? _inicializarFirebase)();
      return (crear ?? () => PushRemotasFirebase.delPlugin(FirebaseMessaging.instance))();
    } on Object catch (e) {
      // Sin el mensaje de la excepción: no hace falta y no se arriesga nada en el log.
      AppLogger.instance.info(
        LogModulo.push,
        'FIREBASE_SIN_CONFIGURAR',
        'Firebase no arrancó: la app sigue sin push remotas',
        {'tipo': e.runtimeType.toString()},
      );
      return null;
    }
  }

  static Future<void> _inicializarFirebase() async {
    await Firebase.initializeApp();
  }

  @override
  Stream<MensajePush> get conLaAppAbierta => _alFrente;

  @override
  Stream<MensajePush> get tocadas => _tocadas;

  @override
  Future<MensajePush?> tomarLaQueAbrioLaApp() async {
    // La marca va antes del await: dos llamadas seguidas no pueden llevarse las dos el mensaje.
    if (_yaSeTomo) return null;
    _yaSeTomo = true;
    final mensaje = await _laQueAbrioLaApp();
    return mensaje == null ? null : _aMensaje(mensaje);
  }

  static Stream<RemoteMessage> _deDifusion(Stream<RemoteMessage> fuente) =>
      fuente.isBroadcast ? fuente : fuente.asBroadcastStream();

  /// Solo el `data`, copiado: lo que venga ahí se sigue leyendo como no confiable más adelante.
  static MensajePush _aMensaje(RemoteMessage mensaje) =>
      MensajePush(Map<String, Object?>.of(mensaje.data));
}
