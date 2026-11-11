import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../logging/app_logger.dart';

/// El canal de Android de las push remotas (HU-NOT-003, #614): ahí dibuja el sistema el título fijo
/// del servidor con la app cerrada o en segundo plano.
///
/// `push-fcm` no manda `channel_id`: el manifest lo declara como canal por defecto de FCM
/// (`com.google.firebase.messaging.default_notification_channel_id`). Sin él, o si el canal todavía
/// no existe, Android usa el de reserva de FCM («Varios»). Nombre y descripción: decisión del 11/11
/// (P3 de #614), al lado de «Recordatorios de visitas».
abstract final class CanalAvisosCampania {
  /// El mismo valor que la meta-data del manifest.
  static const String id = 'avisos_campania';
  static const String nombre = 'Avisos de tu campaña';
  static const String descripcion =
      'Pedidos, depósitos, zonas y cuotas que te avisa la coordinación';

  static const AndroidNotificationChannel canal = AndroidNotificationChannel(
    id,
    nombre,
    description: descripcion,
    importance: Importance.high,
  );

  /// Crea el canal (si ya existe, Android solo actualiza el nombre y la descripción). [crearCanal]
  /// es el del plugin de Android; `null` fuera de Android, y entonces no hace nada. Si falla, la
  /// app sigue: las push caen en el canal de reserva de FCM.
  static Future<void> crear(
    Future<void> Function(AndroidNotificationChannel canal)? crearCanal,
  ) async {
    if (crearCanal == null) return;
    try {
      await crearCanal(canal);
    } on Object catch (e) {
      AppLogger.instance.warn(
        LogModulo.push,
        'CANAL_PUSH_FAIL',
        'no se pudo crear el canal de las push',
        {'tipo': e.runtimeType.toString()},
      );
    }
  }
}
