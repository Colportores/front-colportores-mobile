import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../../core/logging/app_logger.dart';
import '../../../../core/notificaciones/permiso_alarmas_exactas.dart';
import 'motor_de_avisos.dart';

/// [MotorDeAvisos] sobre `flutter_local_notifications`.
///
/// - **La hora se manda en UTC** (`tz.UTC`): el aviso es un instante, no una hora de pared, así que no
///   hace falta la base de zonas horarias ni saber en qué zona está el teléfono, y un cambio de zona
///   o de horario de verano no lo corre.
/// - **El permiso no lo pide el plugin** (`request…Permission: false`): lo pide la vista 24
///   (`PermisoNotificacionesCanal`).
/// - **Android, modo del aviso** («Aviso exacto», decisión de Cristian del 27/10): exacto
///   ([modoExacto]) si el permiso «Alarmas y recordatorios» está prendido (o el Android es anterior
///   al 12, que no lo pide); si no, inexacto ([modoInexacto]), que con el teléfono en reposo Android
///   puede correr hasta una hora. El permiso se lee en cada [programar] por [PermisoAlarmasExactas]
///   (no por el plugin) y, si Android lo revocó entre la lectura y el aviso, se reintenta inexacto:
///   programar el recordatorio nunca falla por esto.
/// - El texto queda en las preferencias del plugin hasta que el aviso suena o se cancela.
final class MotorDeAvisosPlugin implements MotorDeAvisos {
  MotorDeAvisosPlugin(this._plugin, {this._alarmas, AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final FlutterLocalNotificationsPlugin _plugin;

  /// Sin él (tests viejos, app sin canal nativo) todo aviso es inexacto, como antes.
  final PermisoAlarmasExactas? _alarmas;
  final AppLogger _log;

  /// Código con el que el plugin rechaza una alarma exacta sin el permiso.
  static const String _sinPermisoExacto = 'exact_alarms_not_permitted';

  /// Canal de Android de los recordatorios de visitas.
  static const String canalId = 'recordatorios_visitas';
  static const String canalNombre = 'Recordatorios de visitas';
  static const String canalDescripcion = 'Avisos antes de cada visita agendada';

  /// Aviso a la hora justa, aun con el teléfono en reposo (necesita `SCHEDULE_EXACT_ALARM`).
  static const AndroidScheduleMode modoExacto = AndroidScheduleMode.exactAllowWhileIdle;

  /// Aviso sin permiso especial: con el teléfono en reposo puede llegar tarde (hasta una hora en el
  /// peor caso de Android).
  static const AndroidScheduleMode modoInexacto = AndroidScheduleMode.inexactAllowWhileIdle;

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

  /// El modo de ahora: exacto solo si el sistema dice que las alarmas exactas están permitidas. Si
  /// no se puede saber, inexacto: el aviso llega igual, quizá tarde.
  Future<AndroidScheduleMode> _modo() async {
    final alarmas = _alarmas;
    if (alarmas == null) return modoInexacto;
    try {
      return await alarmas.leerEstado() == EstadoAlarmasExactas.permitidas
          ? modoExacto
          : modoInexacto;
    } on Object catch (e) {
      _log.warn(
        LogModulo.agenda,
        'RECORDATORIO_ALARMAS_EXACTAS',
        'no se pudo leer si las alarmas exactas están permitidas; el aviso va inexacto',
        {'error': e.runtimeType.toString()},
      );
      return modoInexacto;
    }
  }

  @override
  Future<void> programar({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime instante,
    required String payload,
  }) async {
    Future<void> en(AndroidScheduleMode modo) => _plugin.zonedSchedule(
      id: id,
      scheduledDate: tz.TZDateTime.from(instante.toUtc(), tz.UTC),
      notificationDetails: _detalles,
      androidScheduleMode: modo,
      title: titulo,
      body: cuerpo,
      payload: payload,
    );

    final modo = await _modo();
    try {
      await en(modo);
    } on PlatformException catch (e) {
      if (modo != modoExacto || e.code != _sinPermisoExacto) rethrow;
      // Android quitó el permiso entre la lectura y el aviso: mejor tarde que nunca.
      await en(modoInexacto);
    }
  }

  @override
  Future<void> cancelar(int id) => _plugin.cancel(id: id);
}
