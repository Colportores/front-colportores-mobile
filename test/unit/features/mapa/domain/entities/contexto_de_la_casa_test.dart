// Qué persona muestra el resumen de la casa (vista 39, C·01): la que más debe; si nadie debe, la primera.
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:test/test.dart';

import '../../../../../helpers/persona_falsos.dart';

void main() {
  final ana = clienteDePersonas('p-1', 'Ana', apellido: 'Rey');
  final beto = clienteDePersonas('p-2', 'Beto', apellido: 'Paz', minutos: 1);
  final carla = clienteDePersonas('p-3', 'Carla', apellido: 'Sosa', minutos: 2);

  test('sin personas no hay persona destacada', () {
    expect(const ContextoDeLaCasa().personaDestacada, isNull);
  });

  test('con una sola persona es esa, deba o no', () {
    expect(ContextoDeLaCasa(personas: [ana]).personaDestacada, ana);
    expect(
      ContextoDeLaCasa(personas: [ana], saldosCentavos: const {'p-1': 5000}).personaDestacada,
      ana,
    );
  });

  test('si nadie debe, es la primera (la más vieja)', () {
    expect(ContextoDeLaCasa(personas: [ana, beto, carla]).personaDestacada, ana);
    expect(
      ContextoDeLaCasa(
        personas: [ana, beto],
        saldosCentavos: const {'p-1': 0, 'p-2': 0},
      ).personaDestacada,
      ana,
    );
  });

  test('si alguien debe, es la que más debe', () {
    final contexto = ContextoDeLaCasa(
      personas: [ana, beto, carla],
      saldosCentavos: const {'p-1': 100000, 'p-2': 250000, 'p-3': 0},
    );
    expect(contexto.personaDestacada, beto);
  });

  test('a igual deuda gana la primera', () {
    final contexto = ContextoDeLaCasa(
      personas: [ana, beto],
      saldosCentavos: const {'p-1': 5000, 'p-2': 5000},
    );
    expect(contexto.personaDestacada, ana);
  });

  test('saldoDe devuelve lo que debe solo si es más que cero', () {
    const contexto = ContextoDeLaCasa(saldosCentavos: {'p-1': 120000, 'p-2': 0, 'p-3': -500});
    expect(contexto.saldoDe('p-1'), 120000);
    expect(contexto.saldoDe('p-2'), isNull);
    expect(contexto.saldoDe('p-3'), isNull);
    expect(contexto.saldoDe('p-9'), isNull);
  });

  test('el toString no imprime nombres ni la nota (PII)', () {
    final texto = ContextoDeLaCasa(personas: [ana]).toString();
    expect(texto, isNot(contains('Ana')));
  });
}
