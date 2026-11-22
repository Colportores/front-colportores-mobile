import 'dart:io';

import 'package:colportores_mobile/core/notificaciones/canal_avisos_campania.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CanalAvisosCampania (P3 de #614)', () {
    test('dado Android, cuando arranca, entonces crea el canal con el nombre y la descripción '
        'decididos', () async {
      final creados = <AndroidNotificationChannel>[];

      await CanalAvisosCampania.crear((canal) async => creados.add(canal));

      expect(creados, hasLength(1));
      final canal = creados.single;
      expect(canal.id, 'avisos_campania');
      expect(canal.name, 'Avisos de tu campaña');
      expect(canal.description, 'Pedidos, depósitos, zonas y cuotas que te avisa la coordinación');
      expect(canal.importance, Importance.high);
    });

    test('dado que no es Android, cuando arranca, entonces no hace nada', () {
      expect(CanalAvisosCampania.crear(null), completes);
    });

    test('dado que el plugin falla al crearlo, cuando arranca, entonces la app sigue', () async {
      await expectLater(
        CanalAvisosCampania.crear((_) async => throw StateError('canal nativo caído')),
        completes,
      );
    });

    test('dado el manifest, entonces le da a FCM este canal por defecto', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final declaracion = RegExp(
        r'android:name="com\.google\.firebase\.messaging\.default_notification_channel_id"\s+'
        r'android:value="([^"]+)"',
      ).firstMatch(manifest);

      expect(declaracion?.group(1), CanalAvisosCampania.id);
    });
  });
}
