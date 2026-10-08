// Test de dominio: Dart puro (CLAUDE.md §Tests). Las horas se arman en la zona del dispositivo,
// como las ve el colportor, para no depender del huso de quien corre los tests.
import 'package:colportores_mobile/features/jornada/domain/jornada_sin_cerrar.dart';
import 'package:test/test.dart';

void main() {
  const margen = Duration(minutes: 30);

  group('JornadaSinCerrar.quedoAbierta', () {
    test('should be false when the jornada started today', () {
      expect(
        JornadaSinCerrar.quedoAbierta(
          inicio: DateTime(2026, 9, 23, 8),
          ahora: DateTime(2026, 9, 23, 14, 35),
          margen: margen,
        ),
        isFalse,
      );
    });

    test('should be true when even the earliest minute of the margin is on a later day', () {
      expect(
        JornadaSinCerrar.quedoAbierta(
          inicio: DateTime(2026, 9, 22, 18),
          ahora: DateTime(2026, 9, 23, 8),
          margen: margen,
        ),
        isTrue,
      );
    });

    test('should be false while the margin still reaches the day of the inicio', () {
      // 00:10: ahora − 30 min = 23:40 de ayer, todavía el día del inicio (es un cierre normal).
      expect(
        JornadaSinCerrar.quedoAbierta(
          inicio: DateTime(2026, 9, 22, 20),
          ahora: DateTime(2026, 9, 23, 0, 10),
          margen: margen,
        ),
        isFalse,
      );
    });

    test(
      'should be false when the inicio is later than the margin even if it crosses midnight',
      () {
        // Iniciada a las 23:59, a las 00:05: el piso es el inicio (23:59), el mismo día.
        expect(
          JornadaSinCerrar.quedoAbierta(
            inicio: DateTime(2026, 9, 22, 23, 59),
            ahora: DateTime(2026, 9, 23, 0, 5),
            margen: margen,
          ),
          isFalse,
        );
      },
    );

    test('should be true once the margin falls entirely on the next day', () {
      expect(
        JornadaSinCerrar.quedoAbierta(
          inicio: DateTime(2026, 9, 22, 23, 59),
          ahora: DateTime(2026, 9, 23, 0, 31),
          margen: margen,
        ),
        isTrue,
      );
    });
  });

  group('JornadaSinCerrar.caeEnOtroDia', () {
    test('should compare calendar days in the device zone, not the elapsed time', () {
      final inicio = DateTime(2026, 9, 22, 23, 59);

      expect(JornadaSinCerrar.caeEnOtroDia(inicio, DateTime(2026, 9, 22, 23, 59, 59)), isFalse);
      expect(JornadaSinCerrar.caeEnOtroDia(inicio, DateTime(2026, 9, 23)), isTrue);
    });
  });

  group('JornadaSinCerrar.primerMinutoDelFin', () {
    test('should be the minute after the inicio, ignoring its seconds', () {
      final inicio = DateTime(2026, 9, 22, 18, 0, 40);

      expect(JornadaSinCerrar.primerMinutoDelFin(inicio), DateTime(2026, 9, 22, 18, 1).toUtc());
    });

    test('should cross midnight for a jornada started at 23:59', () {
      expect(
        JornadaSinCerrar.primerMinutoDelFin(DateTime(2026, 9, 22, 23, 59)),
        DateTime(2026, 9, 23).toUtc(),
      );
    });
  });

  group('JornadaSinCerrar.topeDelFin', () {
    test('should be 12 hours after the inicio when that is already in the past', () {
      expect(
        JornadaSinCerrar.topeDelFin(
          inicio: DateTime(2026, 9, 22, 18),
          ahora: DateTime(2026, 9, 23, 10),
        ),
        DateTime(2026, 9, 23, 6).toUtc(),
      );
    });

    test('should be ahora when fewer than 12 hours have passed (no future hours)', () {
      expect(
        JornadaSinCerrar.topeDelFin(
          inicio: DateTime(2026, 9, 22, 22),
          ahora: DateTime(2026, 9, 23, 1),
        ),
        DateTime(2026, 9, 23, 1).toUtc(),
      );
    });

    test('should accept exactly 12 hours after the inicio', () {
      expect(
        JornadaSinCerrar.topeDelFin(
          inicio: DateTime(2026, 9, 22, 23, 59),
          ahora: DateTime(2026, 9, 24),
        ),
        DateTime(2026, 9, 23, 11, 59).toUtc(),
      );
    });
  });
}
