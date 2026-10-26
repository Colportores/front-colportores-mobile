// Cómo se escribe la fecha de una nota (canvas 32E: «HOY 14:20», «05/10»).
import 'package:colportores_mobile/features/mapa/presentation/textos_notas.dart';
import 'package:test/test.dart';

import '../../../../helpers/nota_persona_falsos.dart';

void main() {
  // Horas locales: el formato lee `toLocal()`, así que los tests no dependen de la zona de la máquina.
  final ahora = DateTime(2026, 10, 22, 15, 5);

  test('dado una nota de hoy, cuando se escribe la fecha, es «HOY» y la hora con dos dígitos', () {
    expect(
      FormatoNotas.fecha(notaDePrueba('a', 'x', creada: DateTime(2026, 10, 22, 14, 20)), ahora),
      'HOY 14:20',
    );
    expect(
      FormatoNotas.fecha(notaDePrueba('a', 'x', creada: DateTime(2026, 10, 22, 7, 5)), ahora),
      'HOY 07:05',
    );
  });

  test('dado una nota de otro día de este año, cuando se escribe la fecha, es «05/10»', () {
    expect(
      FormatoNotas.fecha(notaDePrueba('a', 'x', creada: DateTime(2026, 10, 5, 9)), ahora),
      '05/10',
    );
  });

  test('dado una nota de otro año, cuando se escribe la fecha, lleva el año de dos dígitos', () {
    expect(
      FormatoNotas.fecha(notaDePrueba('a', 'x', creada: DateTime(2025, 1, 9, 9)), ahora),
      '09/01/25',
    );
  });

  test('dado una nota de ayer a la noche, cuando es hoy después de medianoche, no es «HOY»', () {
    final despuesDeMedianoche = DateTime(2026, 10, 23, 0, 10);

    expect(
      FormatoNotas.fecha(
        notaDePrueba('a', 'x', creada: DateTime(2026, 10, 22, 23, 50)),
        despuesDeMedianoche,
      ),
      '22/10',
    );
  });

  test(
    'dado una nota, cuando se escribe el título de su hoja, dice «de hoy 14:20» o «del 05/10»',
    () {
      expect(
        FormatoNotas.tituloDelMenu(
          notaDePrueba('a', 'x', creada: DateTime(2026, 10, 22, 14, 20)),
          ahora,
        ),
        'Nota de hoy 14:20',
      );
      expect(
        FormatoNotas.tituloDelMenu(notaDePrueba('a', 'x', creada: DateTime(2026, 10, 5, 9)), ahora),
        'Nota del 05/10',
      );
    },
  );

  test('dado una nota, cuando se la lee en voz alta, la fecha se dice entera', () {
    expect(
      FormatoNotas.fechaParaLector(
        notaDePrueba('a', 'x', creada: DateTime(2026, 10, 22, 14, 20)),
        ahora,
      ),
      'hoy a las 14:20',
    );
    expect(
      FormatoNotas.fechaParaLector(notaDePrueba('a', 'x', creada: DateTime(2026, 10, 5, 9)), ahora),
      'el 05/10',
    );
  });

  test('dado los textos con cantidades, cuando se arman, nombran lo que cuentan', () {
    expect(TextosNotas.titulo('María'), 'Notas de María');
    expect(TextosNotas.verBorradas(3), 'Ver borradas (3)');
    expect(
      TextosNotas.noPudimosLeer('María'),
      'No pudimos leer las notas de María en tu teléfono.',
    );
    expect(TextosNotas.noPudimosLeer(null), 'No pudimos leer las notas en tu teléfono.');
    expect(TextosNotas.noPudimosLeer('  '), 'No pudimos leer las notas en tu teléfono.');
    expect(TextosNotas.notaLarga(5200), contains('5200'));
    expect(TextosNotas.notaLarga(5200), contains('5000'));
  });
}
