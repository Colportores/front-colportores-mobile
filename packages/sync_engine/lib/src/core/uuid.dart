// UUID v7, en Dart puro.
//
// v7 y no v4 porque el contrato lo pide en §7: la PK la genera el dispositivo y
// tiene que ser **ordenable por tiempo**. Un v4 al azar como PK convierte cada
// insert en una escritura en medio del índice de Postgres; un v7 empieza por el
// timestamp, así que las filas entran al final, que es donde el índice quiere
// que entren.
//
// Que esté acá adentro y no en `package:uuid` es a propósito: son treinta
// líneas y evita una dependencia más en el núcleo.

import 'dart:math';

/// RFC 9562 §5.7.
///
/// ```
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// ┌───────────────────────────────────────────────────────────────┐
/// │                     unix_ts_ms (48 bits)                      │
/// ├───────┬───────────────┬───┬───────────────────────────────────┤
/// │ ver=7 │  rand_a (12)  │var│           rand_b (62)             │
/// └───────┴───────────────┴───┴───────────────────────────────────┘
/// ```
class UuidV7 {
  UuidV7({Random? random, DateTime Function()? clock})
      : _rnd = random ?? Random.secure(),
        _clock = clock ?? DateTime.now;

  final Random _rnd;
  final DateTime Function() _clock;

  int _ultimoMs = 0;
  int _contador = 0;

  String next() {
    final ms = _clock().millisecondsSinceEpoch;

    // Dos jobs en el mismo milisegundo tienen que seguir saliendo en orden: el
    // contador ocupa rand_a, que es justo el campo que RFC 9562 reserva para
    // esto. Sin él, el orden de dos ventas del mismo instante sería al azar.
    if (ms == _ultimoMs) {
      _contador++;
    } else {
      _ultimoMs = ms;
      _contador = _rnd.nextInt(1 << 10);
    }
    final randA = _contador & 0xfff;

    final b = List<int>.filled(16, 0);
    for (var i = 0; i < 6; i++) {
      b[i] = (ms >> (40 - i * 8)) & 0xff; // unix_ts_ms, big-endian
    }
    b[6] = 0x70 | (randA >> 8); // versión 7
    b[7] = randA & 0xff;
    for (var i = 8; i < 16; i++) {
      b[i] = _rnd.nextInt(256);
    }
    b[8] = (b[8] & 0x3f) | 0x80; // variante RFC 4122

    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
