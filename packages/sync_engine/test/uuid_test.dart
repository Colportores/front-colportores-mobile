// UUID v7 (RFC 9562 §5.7). Es la PK que genera el dispositivo, y de eso depende
// que el replay de §7 sea idempotente.

import 'dart:math';

import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

final _formato = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

void main() {
  test('tiene el formato, la versión 7 y la variante RFC', () {
    final uuid = UuidV7();
    for (var i = 0; i < 200; i++) {
      expect(uuid.next(), matches(_formato));
    }
  });

  test('el timestamp va adelante y en big-endian', () {
    final momento = DateTime.utc(2026, 11, 13, 8);
    final generado = UuidV7(clock: () => momento).next();

    final ms = int.parse(generado.substring(0, 8) + generado.substring(9, 13),
        radix: 16);
    expect(ms, momento.millisecondsSinceEpoch);
  });

  test('ordena por tiempo: ordenar como texto es ordenar por fecha', () {
    var ms = DateTime.utc(2026, 11, 13).millisecondsSinceEpoch;
    final uuid = UuidV7(
        clock: () => DateTime.fromMillisecondsSinceEpoch(ms += 1, isUtc: true));

    final generados = [for (var i = 0; i < 100; i++) uuid.next()];
    expect(generados, orderedEquals([...generados]..sort()),
        reason:
            'un v4 al azar como PK escribe en medio del índice de Postgres');
  });

  test('dentro del mismo milisegundo también ordena', () {
    // El reloj no avanza: solo el contador de rand_a los separa.
    final fijo = DateTime.utc(2026, 11, 13);
    final uuid = UuidV7(clock: () => fijo);

    final generados = [for (var i = 0; i < 500; i++) uuid.next()];
    expect(generados, orderedEquals([...generados]..sort()),
        reason: 'dos ventas del mismo instante no pueden quedar al azar');
    expect(generados.toSet(), hasLength(500));
  });

  test('no se repite ni con un generador pobre', () {
    // Random(1) es determinista: si la unicidad dependiera solo del azar, esto
    // colisionaría.
    final uuid = UuidV7(random: Random(1), clock: () => DateTime.utc(2026));
    final generados = {for (var i = 0; i < 5000; i++) uuid.next()};
    expect(generados, hasLength(5000));
  });
}
