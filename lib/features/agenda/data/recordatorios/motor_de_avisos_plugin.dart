import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'motor_de_avisos.dart';

/// [MotorDeAvisos] sobre `flutter_local_notifications`.
///
/// - **La hora se manda en UTC** (`tz.UTC`): el aviso es un instante, no una hora de pared, así que no
///   hace falta la base de zonas horarias ni saber en qué zona está el teléfono, y un cambio de zona
///   o de horario de verano no lo corre.
/// - **El permiso no lo pide el plugin** (`request…Permission: false`): lo pide la vista 24
///   (`PermisoNotificacionesCanal`).
/// - **Android, modo del aviso**: [modoAndroid]. Es el único lugar donde se decide si el aviso es
///   exacto; hoy es el que no necesita permisos especiales (pendiente de decisión, ver el PR).
/// - El texto queda en las preferencias del plugin hasta que el aviso suena o se cancela.
final class MotorDeAvisosPlugin implements MotorDeAvisos {
  MotorDeAvisosPlugin(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  /// Canal de Android de los recordatorios de visitas.
  static const String canalId = 'recordatorios_visitas';
  static const String canalNombre = 'Recordatorios de visitas';
  static const String canalDescripcion = 'Avisos antes de cada visita agendada';

  /// Cómo se programa el aviso en Android: sin alarma exacta (`SCHEDULE_EXACT_ALARM` /
  /// `USE_EXACT_ALARM` están sujetos a permisos y a la política de la tienda). Con el teléfono en
  /// reposo el aviso puede llegar con unos minutos de corrimiento.
  static const AndroidScheduleMode modoAndroid = AndroidScheduleMode.inexactAllowWhileIdle;

  static const NotificationDetails _detalles = NotificationDetails(
    android: AndroidNotificationDetails(
      canalId,
      canalNombre,
      channelDescription: canalDescripcion,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
    iOS: DarwinNotificationDetails(),
  );

  @override
  Future<void> iniciar({required void Function(String? payload) alTocar}) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (respuesta) => alTocar(respuesta.payload),
    );
  }

  @override
  Future<String?> payloadQueAbrioLaApp() async {
    final lanzamiento = await _plugin.getNotificationAppLaunchDetails();
    if (lanzamiento == null || !lanzamiento.didNotificationLaunchApp) return null;
    return lanzamiento.notificationResponse?.payload;
  }

  @override
  Future<void> programar({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime instante,
    required String payload,
  }) => _plugin.zonedSchedule(
    id: id,
    scheduledDate: tz.TZDateTime.from(instante.toUtc(), tz.UTC),
    notificationDetails: _detalles,
    androidScheduleMode: modoAndroid,
    title: titulo,
    body: cuerpo,
    payload: payload,
  );

  @override
  Future<void> cancelar(int id) => _plugin.cancel(id: id);
}
