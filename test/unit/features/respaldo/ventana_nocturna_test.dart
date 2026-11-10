// La ventana nocturna del respaldo (HU-SYNC-005, #583): 03:00 hora local, la de hoy si todavía no
// llegó y la de mañana si ya pasó.
import 'package:colportores_mobile/features/respaldo/domain/services/ventana_nocturna.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('esperaHastaLaVentanaNocturna', () {
    test('dado las 22:00, cuando se programa, faltan 5 horas (las 03:00 de mañana)', () {
      expect(esperaHastaLaVentanaNocturna(DateTime(2026, 11, 2, 22)), const Duration(hours: 5));
    });

    test('dado la 01:30, cuando se programa, faltan 90 minutos (las 03:00 de hoy)', () {
      expect(
        esperaHastaLaVentanaNocturna(DateTime(2026, 11, 3, 1, 30)),
        const Duration(minutes: 90),
      );
    });

    test('dadas las 03:00 en punto, la ventana es la de mañana: 24 horas', () {
      expect(esperaHastaLaVentanaNocturna(DateTime(2026, 11, 3, 3)), const Duration(hours: 24));
    });

    test('dadas las 03:01, faltan 23 horas y 59 minutos', () {
      expect(
        esperaHastaLaVentanaNocturna(DateTime(2026, 11, 3, 3, 1)),
        const Duration(hours: 23, minutes: 59),
      );
    });

    test('dado el fin de mes, mañana es el día 1 del mes que sigue', () {
      expect(
        esperaHastaLaVentanaNocturna(DateTime(2026, 11, 30, 23, 59)),
        const Duration(hours: 3, minutes: 1),
      );
      expect(esperaHastaLaVentanaNocturna(DateTime(2026, 12, 31, 12)), const Duration(hours: 15));
    });

    test('una hora UTC se cuenta en hora local, que es la de la persona', () {
      final local = DateTime(2026, 11, 2, 22);

      expect(esperaHastaLaVentanaNocturna(local.toUtc()), const Duration(hours: 5));
    });

    test('otra hora de ventana se respeta', () {
      expect(
        esperaHastaLaVentanaNocturna(DateTime(2026, 11, 2, 22), hora: 4),
        const Duration(hours: 6),
      );
    });
  });
}
