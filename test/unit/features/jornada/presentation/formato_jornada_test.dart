import 'package:colportores_mobile/features/jornada/presentation/formato_jornada.dart';
import 'package:test/test.dart';

void main() {
  group('formato_jornada', () {
    test('horaCorta: HH:MM en hora local, con ceros', () {
      expect(horaCorta(DateTime(2026, 9, 23, 9, 5)), '09:05');
      expect(horaCorta(DateTime(2026, 9, 23, 14, 35, 59)), '14:35');
    });

    test('fechaLarga: día de la semana, día y mes en español', () {
      expect(fechaLarga(DateTime(2026, 9, 23)), 'miércoles 23 de septiembre');
      expect(fechaLarga(DateTime(2026, 9, 27)), 'domingo 27 de septiembre');
      expect(fechaLarga(DateTime(2026, 1, 5)), 'lunes 5 de enero');
    });

    test('duracionCorta: minutos, horas y horas con minutos', () {
      expect(duracionCorta(const Duration(seconds: 40)), 'menos de 1 min');
      expect(duracionCorta(const Duration(minutes: 12)), '12 min');
      expect(duracionCorta(const Duration(hours: 2)), '2 h');
      expect(duracionCorta(const Duration(hours: 1, minutes: 20)), '1 h 20 min');
    });
  });
}
