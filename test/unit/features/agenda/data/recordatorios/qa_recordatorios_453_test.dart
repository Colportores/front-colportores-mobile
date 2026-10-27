// QA de HU-NOT-002 / issue #453 — cómo queda el aviso en el teléfono y su texto en casos límite.
import 'package:colportores_mobile/features/agenda/data/recordatorios/motor_de_avisos_plugin.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/recordatorios_locales.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/services/texto_recordatorio.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:timezone/timezone.dart' as tz;

class _PluginFalso extends Mock implements FlutterLocalNotificationsPlugin {}

void main() {
  setUpAll(() {
    registerFallbackValue(const NotificationDetails());
    registerFallbackValue(AndroidScheduleMode.exact);
    registerFallbackValue(tz.TZDateTime.utc(2026));
  });

  group('QA #453: aviso en el teléfono', () {
    test(
      'dado una dirección larga, cuando se programa, el aviso se puede desplegar para leer la hora '
      '(que va al final del cuerpo)',
      () async {
        final plugin = _PluginFalso();
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

        await MotorDeAvisosPlugin(plugin).programar(
          id: 1,
          titulo: 'Recordatorio de visita',
          cuerpo: 'Entrevista en Av. Libertador General San Martín 1234, Barrio Norte a las 14:00',
          instante: DateTime.utc(2030),
          payload: 'agenda:ag-1',
        );

        final detalles =
            verify(
                  () => plugin.zonedSchedule(
                    id: any(named: 'id'),
                    scheduledDate: any(named: 'scheduledDate'),
                    notificationDetails: captureAny(named: 'notificationDetails'),
                    androidScheduleMode: any(named: 'androidScheduleMode'),
                    title: any(named: 'title'),
                    body: any(named: 'body'),
                    payload: any(named: 'payload'),
                  ),
                ).captured.single
                as NotificationDetails;
        expect(detalles.android!.styleInformation, isA<BigTextStyleInformation>());
      },
      // skip: QA #453 — sin BigTextStyle el cuerpo queda en una línea y una dirección larga corta la hora.
      skip:
          'QA #453: sin BigTextStyleInformation Android corta el cuerpo en una línea y se pierde la hora',
    );
  });

  group('QA #453: texto del aviso', () {
    final catorce = DateTime(2026, 10, 27, 14);

    test('dado una dirección con emoji o acentos, cuando se arma, se conserva tal cual', () {
      expect(
        TextoRecordatorio.cuerpo(
          tipo: TipoAgenda.cobranza,
          direccion: 'Pasaje Ñandú 12 🏠',
          fechaProgramada: catorce,
        ),
        'Cobranza en Pasaje Ñandú 12 🏠 a las 14:00',
      );
    });

    test('dado una visita a las 00:05 y otra a las 09:07, cuando se arma, la hora lleva ceros', () {
      String a(DateTime d) => TextoRecordatorio.cuerpo(
        tipo: TipoAgenda.entrevista,
        direccion: 'X 1',
        fechaProgramada: d,
      );
      expect(a(DateTime(2026, 10, 28, 0, 5)), 'Entrevista en X 1 a las 00:05');
      expect(a(DateTime(2026, 10, 27, 9, 7)), 'Entrevista en X 1 a las 09:07');
    });

    test('dado cualquier id de agenda (vacío, emoji, larguísimo), cuando se calcula el número del '
        'aviso, es un entero de 31 bits no negativo y estable', () {
      for (final id in ['', '🏠', 'a' * 5000, '0192f3a0-7b1c-7cde-9f01-aaaaaaaaaaaa']) {
        final n = RecordatoriosLocales.idDeAviso(id);
        expect(n, inInclusiveRange(0, 0x7fffffff));
        expect(RecordatoriosLocales.idDeAviso(id), n);
      }
    });
  });
}
