// «Hoy» para las réplicas con fechas `date`: el día de calendario de Montevideo, no el de la zona
// horaria del teléfono ni el de UTC (docs 08 §8.6; backend 0024 `hoy_montevideo()`).
import 'package:colportores_mobile/core/database/dia_de_calendario.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('diaDeCalendario', () {
    test(
      'a las 22:00 de Montevideo del último día todavía es ese día, aunque en UTC ya sea mañana',
      () {
        expect(diaDeCalendario(DateTime.utc(2026, 10, 28, 1)), '2026-10-27');
      },
    );

    test('a la medianoche de Montevideo cambia el día', () {
      expect(diaDeCalendario(DateTime.utc(2026, 10, 28, 2, 59, 59)), '2026-10-27');
      expect(diaDeCalendario(DateTime.utc(2026, 10, 28, 3)), '2026-10-28');
    });

    test(
      'es el mismo día para un instante dado cualquiera sea la zona horaria con que se lo pida',
      () {
        final utc = DateTime.utc(2026, 1, 1, 2);
        final local = DateTime.fromMillisecondsSinceEpoch(utc.millisecondsSinceEpoch);
        expect(diaDeCalendario(utc), '2025-12-31');
        expect(diaDeCalendario(local), '2025-12-31');
      },
    );

    test('rellena con ceros el mes y el día', () {
      expect(diaDeCalendario(DateTime.utc(2026, 3, 5, 15)), '2026-03-05');
    });
  });
}
