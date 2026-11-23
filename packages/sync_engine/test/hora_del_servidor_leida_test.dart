// `server_time` de la respuesta: si el servidor no la mandó o mandó una ilegible, el motor rellena con
// el reloj del equipo (`_fecha`) y lo dice (`serverTimeEsDelServidor`), para que nadie anote la hora del
// equipo como si fuera la del servidor (QA #612).

import 'package:sync_engine/sync_engine.dart';
import 'package:test/test.dart';

void main() {
  group('pull', () {
    test('con server_time legible, es del servidor', () {
      final delta = pullResponseFromJson({
        'server_time': '2026-11-03T15:00:00Z',
      });

      expect(delta.serverTimeEsDelServidor, isTrue);
      expect(delta.serverTime, DateTime.utc(2026, 11, 3, 15));
    });

    test('sin server_time o con uno ilegible, la hora es de relleno', () {
      for (final json in [
        <String, Object?>{},
        {'server_time': 'ayer a la tarde'},
        {'server_time': null},
      ]) {
        final delta = pullResponseFromJson(json);
        expect(delta.serverTimeEsDelServidor, isFalse, reason: '$json');
        expect(delta.serverTime.isUtc, isTrue);
      }
    });
  });

  group('push', () {
    test('con server_time legible, es del servidor', () {
      final r = pushResponseFromJson({
        'server_time': '2026-11-03T15:00:00Z',
        'results': [],
      });

      expect(r.serverTimeEsDelServidor, isTrue);
    });

    test('sin server_time o con uno ilegible, la hora es de relleno', () {
      for (final json in [
        <String, Object?>{'results': <Object?>[]},
        {'server_time': 'ayer a la tarde', 'results': <Object?>[]},
      ]) {
        expect(
          pushResponseFromJson(json).serverTimeEsDelServidor,
          isFalse,
          reason: '$json',
        );
      }
    });
  });
}
