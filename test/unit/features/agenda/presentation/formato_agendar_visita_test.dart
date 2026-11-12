// Cómo se escriben el día y la hora en «Agendar una visita» (#408).
import 'package:colportores_mobile/features/agenda/presentation/formato_agendar_visita.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Viernes 23/10/2026, 14:35.
  final ahora = DateTime(2026, 10, 23, 14, 35);

  group('FormatoAgendarVisita', () {
    test('dada una hora, cuando se escribe, entonces lleva ceros a la izquierda', () {
      expect(FormatoAgendarVisita.hora(DateTime(2026, 1, 1, 9, 5)), '09:05');
      expect(FormatoAgendarVisita.minutosComoHora(14 * 60 + 30), '14:30');
      expect(FormatoAgendarVisita.minutosComoHora(0), '00:00');
    });

    test('dado el día de hoy, cuando se escribe el campo, entonces dice Hoy', () {
      expect(FormatoAgendarVisita.cuando(DateTime(2026, 10, 23, 11), ahora), 'Hoy · 11:00');
    });

    test('dado mañana, cuando se escribe el campo, entonces dice Mañana', () {
      expect(FormatoAgendarVisita.cuando(DateTime(2026, 10, 24, 9), ahora), 'Mañana · 09:00');
    });

    test('dado otro día, cuando se escribe el campo, entonces lleva el día y la fecha', () {
      expect(
        FormatoAgendarVisita.cuando(DateTime(2026, 10, 29, 14, 30), ahora),
        'Jueves 29/10 · 14:30',
      );
      expect(
        FormatoAgendarVisita.cuando(DateTime(2026, 11, 2, 8, 30), ahora),
        'Lunes 02/11 · 08:30',
      );
    });

    test('dado el fin de mes, cuando se escribe mañana, entonces cruza el mes', () {
      expect(
        FormatoAgendarVisita.cuando(DateTime(2026, 11, 1, 9), DateTime(2026, 10, 31, 20)),
        'Mañana · 09:00',
      );
    });

    test('dada la frase de hora pasada, cuando es hoy o antes, entonces la arma', () {
      expect(
        FormatoAgendarVisita.cuandoEnFrase(DateTime(2026, 10, 23, 11), ahora),
        'Hoy a las 11:00',
      );
      expect(
        FormatoAgendarVisita.cuandoEnFrase(DateTime(2026, 10, 12, 11), ahora),
        'El lun 12/10 a las 11:00',
      );
    });

    test('dados los chips de día, cuando se escriben, entonces son de tres letras', () {
      expect(FormatoAgendarVisita.diaCorto(DateTime(2026, 10, 24)), 'Sáb 24');
      expect(FormatoAgendarVisita.diaCorto(DateTime(2026, 10, 26)), 'Lun 26');
    });

    test('dados un nombre y un apellido, cuando se sacan las iniciales, entonces son dos', () {
      expect(FormatoAgendarVisita.iniciales('María', 'Fernández'), 'MF');
      expect(FormatoAgendarVisita.iniciales('maría', ''), 'M');
      expect(FormatoAgendarVisita.iniciales('', ''), '');
      expect(FormatoAgendarVisita.iniciales('  ', 'Pérez'), 'P');
    });
  });
}
