// El turno único de los flujos de la DB local (revisión del PR #81). Dart puro.
import 'dart:async';

import 'package:colportores_mobile/features/auth/domain/services/turno_db_local.dart';
import 'package:test/test.dart';

void main() {
  group('TurnoDbLocal', () {
    test('dados tres flujos que llegan juntos, corren de a uno y en orden de llegada', () async {
      final turno = TurnoDbLocal();
      final orden = <String>[];
      final primero = Completer<void>();

      final a = turno.enExclusiva(() async {
        orden.add('a empieza');
        await primero.future;
        orden.add('a termina');
        return 'a';
      });
      final b = turno.enExclusiva(() async {
        orden.add('b');
        return 'b';
      });
      final c = turno.enExclusiva(() async {
        orden.add('c');
        return 'c';
      });
      await Future<void>.delayed(Duration.zero);
      expect(orden, ['a empieza'], reason: 'b y c esperan');

      primero.complete();

      expect(await Future.wait([a, b, c]), ['a', 'b', 'c']);
      expect(orden.first, 'a empieza');
      expect(orden[1], 'a termina');
      expect(orden.sublist(2), unorderedEquals(['b', 'c']));
    });

    test('dado un flujo que falla, libera el turno y el siguiente corre', () async {
      final turno = TurnoDbLocal();

      final falla = turno.enExclusiva<void>(() async => throw StateError('boom'));
      final siguiente = turno.enExclusiva(() async => 'ok');

      await expectLater(falla, throwsA(isA<StateError>()));
      expect(await siguiente, 'ok');
    });
  });
}
