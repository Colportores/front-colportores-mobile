// HU-NOT-002 / issue #453 — `MotorDeAvisosPlugin` le habla a `flutter_local_notifications` como
// corresponde: la hora va en UTC, el plugin no pide el permiso solo, y un toque reenvía el payload.
import 'package:colportores_mobile/core/notificaciones/fakes/permiso_alarmas_exactas_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_alarmas_exactas.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/motor_de_avisos_plugin.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:timezone/timezone.dart' as tz;

class _PluginFalso extends Mock implements FlutterLocalNotificationsPlugin {}

void main() {
  late _PluginFalso plugin;
  late MotorDeAvisosPlugin motor;

  setUpAll(() {
    registerFallbackValue(const InitializationSettings());
    registerFallbackValue(const NotificationDetails());
    registerFallbackValue(AndroidScheduleMode.exact);
    registerFallbackValue(tz.TZDateTime.utc(2026));
  });

  setUp(() {
    plugin = _PluginFalso();
    motor = MotorDeAvisosPlugin(plugin);
  });

  group('iniciar', () {
    test('dado el arranque, cuando se inicia, el plugin no pide permisos por su cuenta y usa el '
        'ícono de la app', () async {
      when(
        () => plugin.initialize(
          settings: any(named: 'settings'),
          onDidReceiveNotificationResponse: any(named: 'onDidReceiveNotificationResponse'),
          onDidReceiveBackgroundNotificationResponse: any(
            named: 'onDidReceiveBackgroundNotificationResponse',
          ),
        ),
      ).thenAnswer((_) async => true);

      await motor.iniciar(alTocar: (_) {});

      final ajustes =
          verify(
                () => plugin.initialize(
                  settings: captureAny(named: 'settings'),
                  onDidReceiveNotificationResponse: any(named: 'onDidReceiveNotificationResponse'),
                  onDidReceiveBackgroundNotificationResponse: any(
                    named: 'onDidReceiveBackgroundNotificationResponse',
                  ),
                ),
              ).captured.single
              as InitializationSettings;
      expect(ajustes.android!.defaultIcon, '@mipmap/ic_launcher');
      expect(ajustes.iOS!.requestAlertPermission, isFalse);
      expect(ajustes.iOS!.requestBadgePermission, isFalse);
      expect(ajustes.iOS!.requestSoundPermission, isFalse);
    });

    test('dado que la persona toca un aviso, cuando el plugin avisa, llega el payload', () async {
      void Function(NotificationResponse)? alResponder;
      when(
        () => plugin.initialize(
          settings: any(named: 'settings'),
          onDidReceiveNotificationResponse: any(named: 'onDidReceiveNotificationResponse'),
          onDidReceiveBackgroundNotificationResponse: any(
            named: 'onDidReceiveBackgroundNotificationResponse',
          ),
        ),
      ).thenAnswer((invocation) async {
        alResponder =
            invocation.namedArguments[#onDidReceiveNotificationResponse]
                as void Function(NotificationResponse)?;
        return true;
      });
      final tocados = <String?>[];

      await motor.iniciar(alTocar: tocados.add);
      alResponder!(
        const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          payload: 'agenda:ag-1',
        ),
      );

      expect(tocados, ['agenda:ag-1']);
    });
  });

  group('payloadQueAbrioLaApp', () {
    test('dado que la app arrancó por un aviso, cuando se pregunta, devuelve su payload', () async {
      when(() => plugin.getNotificationAppLaunchDetails()).thenAnswer(
        (_) async => const NotificationAppLaunchDetails(
          true,
          notificationResponse: NotificationResponse(
            notificationResponseType: NotificationResponseType.selectedNotification,
            payload: 'agenda:ag-2',
          ),
        ),
      );

      expect(await motor.payloadQueAbrioLaApp(), 'agenda:ag-2');
    });

    test(
      'dado que la app arrancó sola o el sistema no sabe, cuando se pregunta, devuelve null',
      () async {
        when(
          () => plugin.getNotificationAppLaunchDetails(),
        ).thenAnswer((_) async => const NotificationAppLaunchDetails(false));
        expect(await motor.payloadQueAbrioLaApp(), isNull);

        when(() => plugin.getNotificationAppLaunchDetails()).thenAnswer((_) async => null);
        expect(await motor.payloadQueAbrioLaApp(), isNull);

        when(
          () => plugin.getNotificationAppLaunchDetails(),
        ).thenAnswer((_) async => const NotificationAppLaunchDetails(true));
        expect(await motor.payloadQueAbrioLaApp(), isNull);
      },
    );
  });

  group('programar y cancelar', () {
    test('dado un aviso, cuando se programa, el plugin recibe el instante en UTC, el canal de los '
        'recordatorios y, sin saber nada de las alarmas exactas, el modo inexacto', () async {
      when(
        () => plugin.zonedSchedule(
          id: any(named: 'id'),
          scheduledDate: any(named: 'scheduledDate'),
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: any(named: 'androidScheduleMode'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async {});
      final instante = DateTime.utc(2026, 10, 27, 16, 30);

      await motor.programar(
        id: 42,
        titulo: 'Recordatorio de visita',
        cuerpo: 'Entrevista en Av. Italia 1234 a las 14:00',
        instante: instante,
        payload: 'agenda:ag-1',
      );

      final captura = verify(
        () => plugin.zonedSchedule(
          id: captureAny(named: 'id'),
          scheduledDate: captureAny(named: 'scheduledDate'),
          notificationDetails: captureAny(named: 'notificationDetails'),
          androidScheduleMode: captureAny(named: 'androidScheduleMode'),
          title: captureAny(named: 'title'),
          body: captureAny(named: 'body'),
          payload: captureAny(named: 'payload'),
        ),
      ).captured;
      expect(captura[0], 42);
      final fecha = captura[1] as tz.TZDateTime;
      expect(fecha.location.name, 'Etc/UTC');
      expect(fecha.isAtSameMomentAs(instante), isTrue);
      final detalles = captura[2] as NotificationDetails;
      expect(detalles.android!.channelId, MotorDeAvisosPlugin.canalId);
      expect(detalles.android!.importance, Importance.high);
      expect(captura[3], AndroidScheduleMode.inexactAllowWhileIdle);
      expect(captura[3], MotorDeAvisosPlugin.modoInexacto);
      expect(captura[4], 'Recordatorio de visita');
      expect(captura[5], 'Entrevista en Av. Italia 1234 a las 14:00');
      expect(captura[6], 'agenda:ag-1');
    });

    test('dado un instante local, cuando se programa, se manda el mismo momento en UTC', () async {
      when(
        () => plugin.zonedSchedule(
          id: any(named: 'id'),
          scheduledDate: any(named: 'scheduledDate'),
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: any(named: 'androidScheduleMode'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async {});
      final local = DateTime(2026, 10, 27, 13, 30);

      await motor.programar(id: 1, titulo: 't', cuerpo: 'c', instante: local, payload: 'p');

      final fecha =
          verify(
                () => plugin.zonedSchedule(
                  id: any(named: 'id'),
                  scheduledDate: captureAny(named: 'scheduledDate'),
                  notificationDetails: any(named: 'notificationDetails'),
                  androidScheduleMode: any(named: 'androidScheduleMode'),
                  title: any(named: 'title'),
                  body: any(named: 'body'),
                  payload: any(named: 'payload'),
                ),
              ).captured.single
              as tz.TZDateTime;
      expect(fecha.isAtSameMomentAs(local), isTrue);
      expect(fecha.location.name, 'Etc/UTC');
    });

    test('dado un aviso, cuando se cancela, el plugin cancela ese id', () async {
      when(() => plugin.cancel(id: any(named: 'id'))).thenAnswer((_) async {});

      await motor.cancelar(77);

      verify(() => plugin.cancel(id: 77)).called(1);
    });
  });
  group('modo del aviso en Android (#510, «Aviso exacto»)', () {
    late PermisoAlarmasExactasEnMemoria alarmas;
    late List<AndroidScheduleMode> modos;

    void programarEnElPlugin({Object? Function(AndroidScheduleMode modo)? falla}) {
      when(
        () => plugin.zonedSchedule(
          id: any(named: 'id'),
          scheduledDate: any(named: 'scheduledDate'),
          notificationDetails: any(named: 'notificationDetails'),
          androidScheduleMode: any(named: 'androidScheduleMode'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((invocacion) async {
        final modo = invocacion.namedArguments[#androidScheduleMode] as AndroidScheduleMode;
        modos.add(modo);
        final error = falla?.call(modo);
        if (error != null) throw error;
      });
    }

    Future<void> programar() => motor.programar(
      id: 1,
      titulo: 'Recordatorio de visita',
      cuerpo: 'Entrevista en Av. Italia 1234 a las 14:00',
      instante: DateTime.utc(2026, 10, 27, 16, 30),
      payload: 'agenda:ag-1',
    );

    setUp(() {
      alarmas = PermisoAlarmasExactasEnMemoria();
      modos = [];
      motor = MotorDeAvisosPlugin(plugin, alarmas: alarmas);
    });

    test(
      'dado «Alarmas y recordatorios» prendido, cuando se programa, el aviso es exacto',
      () async {
        alarmas.estado = EstadoAlarmasExactas.permitidas;
        programarEnElPlugin();

        await programar();

        expect(modos, [AndroidScheduleMode.exactAllowWhileIdle]);
        expect(MotorDeAvisosPlugin.modoExacto, AndroidScheduleMode.exactAllowWhileIdle);
      },
    );

    test(
      'dado «Alarmas y recordatorios» apagado, cuando se programa, el aviso es inexacto',
      () async {
        alarmas.estado = EstadoAlarmasExactas.apagadas;
        programarEnElPlugin();

        await programar();

        expect(modos, [AndroidScheduleMode.inexactAllowWhileIdle]);
      },
    );

    test('dado un sistema sin ese permiso (iOS), cuando se programa, no pide exacto', () async {
      alarmas.estado = EstadoAlarmasExactas.noAplica;
      programarEnElPlugin();

      await programar();

      expect(modos, [AndroidScheduleMode.inexactAllowWhileIdle]);
    });

    test(
      'dado que el permiso cambia entre un aviso y el siguiente, cada uno usa el de ahora',
      () async {
        programarEnElPlugin();
        alarmas.estado = EstadoAlarmasExactas.apagadas;
        await programar();
        alarmas.estado = EstadoAlarmasExactas.permitidas;
        await programar();
        alarmas.estado = EstadoAlarmasExactas.apagadas;
        await programar();

        expect(modos, [
          AndroidScheduleMode.inexactAllowWhileIdle,
          AndroidScheduleMode.exactAllowWhileIdle,
          AndroidScheduleMode.inexactAllowWhileIdle,
        ]);
      },
    );

    test(
      'dado que el sistema no contesta el permiso, el aviso se programa inexacto y no falla',
      () async {
        alarmas.fallaAlLeer = true;
        programarEnElPlugin();

        await programar();

        expect(modos, [AndroidScheduleMode.inexactAllowWhileIdle]);
      },
    );

    test(
      'dado que Android quitó el permiso justo antes del aviso, se reintenta inexacto',
      () async {
        alarmas.estado = EstadoAlarmasExactas.permitidas;
        programarEnElPlugin(
          falla: (modo) => modo == AndroidScheduleMode.exactAllowWhileIdle
              ? PlatformException(code: 'exact_alarms_not_permitted')
              : null,
        );

        await programar();

        expect(modos, [
          AndroidScheduleMode.exactAllowWhileIdle,
          AndroidScheduleMode.inexactAllowWhileIdle,
        ]);
      },
    );

    test('dado otra falla del plugin con el aviso exacto, se propaga sin reintentar', () async {
      alarmas.estado = EstadoAlarmasExactas.permitidas;
      programarEnElPlugin(falla: (_) => PlatformException(code: 'otra'));

      await expectLater(programar(), throwsA(isA<PlatformException>()));
      expect(modos, [AndroidScheduleMode.exactAllowWhileIdle]);
    });

    test('dado que el aviso inexacto falla, se propaga sin reintentar', () async {
      alarmas.estado = EstadoAlarmasExactas.apagadas;
      programarEnElPlugin(falla: (_) => PlatformException(code: 'exact_alarms_not_permitted'));

      await expectLater(programar(), throwsA(isA<PlatformException>()));
      expect(modos, [AndroidScheduleMode.inexactAllowWhileIdle]);
    });
  });
}
