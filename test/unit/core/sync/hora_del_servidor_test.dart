// La última hora que dijo el servidor (`server_time`) y quién la anota: la usa lo que borra por tiempo
// (las notas borradas hace más de 90 días, HU-UBI-012, #509).
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/sync/hora_del_servidor.dart';
import 'package:colportores_mobile/core/sync/transporte_que_anota_la_hora.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';

import '../../../helpers/logger_mudo.dart';

final class _HoraEnMemoria implements HoraDelServidor {
  final anotadas = <DateTime>[];
  Object? falla;

  @override
  Future<DateTime?> ultima() async => anotadas.isEmpty ? null : anotadas.last;

  @override
  Future<void> registrar(DateTime serverTime) async {
    if (falla != null) throw falla!;
    anotadas.add(serverTime);
  }
}

final class _Interno implements SyncTransport {
  PushResult? resultadoPush;
  PullDelta? delta;
  Object? falla;

  @override
  Future<PushResult> push(PushBatch batch) async {
    if (falla != null) throw falla!;
    return resultadoPush!;
  }

  @override
  Future<PullDelta> pull({required List<String> entities, String? watermark, int? limit}) async {
    if (falla != null) throw falla!;
    return delta!;
  }
}

void main() {
  group('HoraDelServidorEnDb', () {
    late AppDatabase db;
    late HoraDelServidorEnDb hora;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
      hora = HoraDelServidorEnDb(() => db, logger: loggerMudo());
    });
    tearDown(() => db.close());

    test('dado un teléfono que nunca habló con el servidor, no hay hora', () async {
      expect(await hora.ultima(), isNull);
    });

    test('dada una hora del servidor, queda guardada en UTC', () async {
      await hora.registrar(DateTime.utc(2027, 1, 25, 9, 30));

      expect(await hora.ultima(), DateTime.utc(2027, 1, 25, 9, 30));
    });

    test('dada una hora más vieja que la guardada, no la pisa', () async {
      await hora.registrar(DateTime.utc(2027, 1, 25));
      await hora.registrar(DateTime.utc(2027, 1, 20));

      expect(await hora.ultima(), DateTime.utc(2027, 1, 25));
    });

    test('dada una hora más nueva, la reemplaza', () async {
      await hora.registrar(DateTime.utc(2027, 1, 25));
      await hora.registrar(DateTime.utc(2027, 2, 1));

      expect(await hora.ultima(), DateTime.utc(2027, 2, 1));
    });

    test('dado un valor ilegible en la fila, es «no hay dato» y no una excepción', () async {
      await db.customStatement(
        "INSERT INTO sync_meta (clave, valor) VALUES ('${HoraDelServidorEnDb.clave}', 'no es una fecha')",
      );

      expect(await hora.ultima(), isNull);
    });

    test('dada una DB cerrada al escribir, no lanza', () async {
      await db.close();

      await hora.registrar(DateTime.utc(2027));
      db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    });

    test('dada la sesión cerrada (sin DB), no hay hora y registrar no hace nada', () async {
      final sinDb = HoraDelServidorEnDb(() => null, logger: loggerMudo());

      await sinDb.registrar(DateTime.utc(2027));

      expect(await sinDb.ultima(), isNull);
    });

    test(
      'dada la hora guardada, el motor no la toca: DriftSyncMeta sigue leyendo lo suyo',
      () async {
        await hora.registrar(DateTime.utc(2027, 1, 25));
        final filas = await db.select(db.syncMetas).get();

        expect(filas.map((f) => f.clave), [HoraDelServidorEnDb.clave]);
      },
    );
  });

  group('TransporteQueAnotaLaHora', () {
    late _Interno interno;
    late _HoraEnMemoria hora;
    late TransporteQueAnotaLaHora transporte;

    setUp(() {
      interno = _Interno();
      hora = _HoraEnMemoria();
      transporte = TransporteQueAnotaLaHora(interno, hora);
    });

    PushResult push(DateTime serverTime, {String code = ''}) => PushResult(
      serverTime: serverTime,
      results: [
        JobResult(
          clientOpId: 'op-1',
          outcome: code.isEmpty ? JobOutcome.accepted : JobOutcome.invalid,
          code: code,
        ),
      ],
    );

    test('dado un push contestado por el servidor, anota su hora y devuelve lo mismo', () async {
      final esperado = push(DateTime.utc(2027, 1, 25, 9));
      interno.resultadoPush = esperado;

      final r = await transporte.push(const PushBatch([]));

      expect(r, same(esperado));
      expect(hora.anotadas, [DateTime.utc(2027, 1, 25, 9)]);
    });

    test('dado un pull, anota la hora del delta y devuelve lo mismo', () async {
      final delta = PullDelta(
        serverTime: DateTime.utc(2027, 2, 1),
        watermark: 'w1',
        hasMore: false,
        rows: const {},
      );
      interno.delta = delta;

      final r = await transporte.pull(entities: const ['producto'], watermark: 'w0', limit: 10);

      expect(r, same(delta));
      expect(hora.anotadas, [DateTime.utc(2027, 2, 1)]);
    });

    test('dado un push donde un job volvió «lote demasiado grande», no anota: la hora es del '
        'equipo', () async {
      interno.resultadoPush = push(DateTime.now().toUtc(), code: kRpcLoteDemasiadoGrande);

      await transporte.push(const PushBatch([]));

      expect(hora.anotadas, isEmpty);
    });

    test('dada una falla del transporte, sube tal cual y no anota nada', () async {
      interno.falla = const TransportFailure(FailureKind.transient, code: 'HTTP_503');

      await expectLater(transporte.push(const PushBatch([])), throwsA(isA<TransportFailure>()));
      await expectLater(transporte.pull(entities: const []), throwsA(isA<TransportFailure>()));
      expect(hora.anotadas, isEmpty);
    });

    test('dado que anotar falla, el ciclo de sync no se entera', () async {
      hora.falla = StateError('base rota');
      final esperado = push(DateTime.utc(2027));
      interno.resultadoPush = esperado;

      expect(await transporte.push(const PushBatch([])), same(esperado));
    });
  });
}
