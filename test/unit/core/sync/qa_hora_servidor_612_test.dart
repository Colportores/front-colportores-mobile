// QA de #612 (decisión P3 de #509): la limpieza de las notas borradas usa el menor entre el reloj de la
// sesión y la última `server_time` del servidor. Estos tests prueban la cadena entera con piezas reales
// (`SupabaseRpcTransport` con un cliente HTTP falso → `TransporteQueAnotaLaHora` → `HoraDelServidorEnDb`
// sobre Drift en memoria → `LimpiarNotasBorradasUseCase` → borrado real), que los del PR prueban por
// separado y con un transporte falso.
//
// Los hallazgos van con `skip`; `--dart-define=QA_HALLAZGOS=true` los corre para verlos fallar.
import 'dart:convert';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/logging/app_logger.dart';
import 'package:colportores_mobile/core/sync/hora_del_servidor.dart';
import 'package:colportores_mobile/core/sync/transporte_que_anota_la_hora.dart';
import 'package:colportores_mobile/core/usecases/use_case.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/notas_borradas_local_data_source_drift.dart';
import 'package:colportores_mobile/features/mapa/data/datasources/notas_table.dart';
import 'package:colportores_mobile/features/mapa/data/repositories/limpieza_notas_borradas_repository_impl.dart';
import 'package:colportores_mobile/features/mapa/domain/usecases/limpiar_notas_borradas_use_case.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logger/logger.dart';
import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';

import '../../../helpers/logger_mudo.dart';

const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

const _sobre = ClientEnvelope(
  deviceId: '018f2c4e-6b7d-7a11-9f3c-000000000001',
  appVersion: '1.4.2',
);

final class _Salida extends LogOutput {
  final lineas = <String>[];

  @override
  void output(OutputEvent event) => lineas.addAll(event.lines);
}

void main() {
  // «Hoy» real, según el servidor.
  final hoy = DateTime.utc(2026, 11, 3, 15);
  DateTime haceDias(int d) => hoy.subtract(Duration(days: d));

  late AppDatabase db;
  late HoraDelServidorEnDb hora;
  late _Salida salida;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    salida = _Salida();
    hora = HoraDelServidorEnDb(() => db, logger: AppLogger(output: salida));
  });
  tearDown(() => db.close());

  Future<void> nota(String id, {DateTime? borrada, String tipo = TipoObjetivoNota.persona}) => db
      .into(db.notas)
      .insert(
        NotasCompanion.insert(
          id: id,
          targetType: tipo,
          targetId: 'per-1',
          texto: 'texto privado de $id',
          createdAt: haceDias(500),
          updatedAt: haceDias(500),
          createdBy: const Value('col-1'),
          deletedAt: Value(borrada),
        ),
      );

  Future<List<String>> ids() async =>
      [for (final n in await db.select(db.notas).get()) n.id]..sort();

  Future<int> limpiar({required DateTime relojEquipo, HoraDelServidor? servidor}) async {
    final caso = LimpiarNotasBorradasUseCase(
      LimpiezaNotasBorradasRepositoryImpl(
        NotasBorradasLocalDataSourceDrift(db),
        logger: loggerMudo(),
      ),
      ahora: () async => relojEquipo,
      horaDelServidor: (servidor ?? hora).ultima,
    );
    final r = await caso(const NoParams());
    return r.fold((f) => fail('la limpieza falló: $f'), (n) => n);
  }

  Future<void> sembrarTres() async {
    await nota('reciente', borrada: haceDias(60));
    await nota('vencida', borrada: haceDias(95));
    await nota('vieja', borrada: haceDias(400));
    await nota('activa');
    await nota('visita-vieja', borrada: haceDias(400), tipo: TipoObjetivoNota.visita);
  }

  SupabaseRpcTransport rpc(http.Response Function(http.Request) responder) => SupabaseRpcTransport(
    projectUrl: Uri.parse('https://demo.supabase.co'),
    anonKey: 'anon',
    token: () async => 'jwt',
    device: _sobre,
    client: MockClient((r) async => responder(r)),
  );

  http.Response json(Map<String, Object?> cuerpo, [int status = 200]) => http.Response(
    jsonEncode(cuerpo),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  PushBatch loteDe(int n) => PushBatch([
    for (var i = 0; i < n; i++)
      SyncJob(
        clientOpId: 'op-$i',
        entity: 'nota',
        op: Op.insert,
        payload: const {'id': 'x'},
        createdAt: hoy,
      ),
  ]);

  group('la limpieza con la hora del servidor (piezas reales)', () {
    test(
      'dado el teléfono adelantado a 2028 y el servidor en 2026, no borra una nota de 60 días',
      () async {
        await sembrarTres();
        await hora.registrar(hoy);
        final borradas = await limpiar(relojEquipo: DateTime.utc(2028, 5, 1), servidor: hora);
        expect(borradas, 2);
        expect(await ids(), ['activa', 'reciente', 'visita-vieja']);
      },
    );

    test(
      'dado el teléfono atrasado a 2020, no borra nada (el reloj de la sesión no retrocede)',
      () async {
        await sembrarTres();
        await hora.registrar(hoy);
        expect(await limpiar(relojEquipo: DateTime.utc(2020, 1, 1)), 0);
        expect(await ids(), hasLength(5));
      },
    );

    test(
      'dado un teléfono que nunca habló con el servidor, no borra nada aunque haya notas de 400 días',
      () async {
        await sembrarTres();
        expect(await limpiar(relojEquipo: hoy), 0);
        expect(await ids(), hasLength(5));
      },
    );

    test(
      'dada una última hora del servidor de hace 100 días, borra solo lo vencido para ESA hora',
      () async {
        await sembrarTres();
        await hora.registrar(haceDias(100));
        // Al servidor le faltan 100 días: la de 95 días (borrada DESPUÉS de esa hora) queda; la de 400, no.
        expect(await limpiar(relojEquipo: hoy), 1);
        expect(await ids(), ['activa', 'reciente', 'vencida', 'visita-vieja']);
      },
    );

    test(
      'dado un valor ilegible en `sync_meta`, es como no haber hablado: no borra nada',
      () async {
        await sembrarTres();
        await db.customStatement(
          "INSERT INTO sync_meta (clave, valor) VALUES ('${HoraDelServidorEnDb.clave}', 'mañana')",
        );
        expect(await limpiar(relojEquipo: hoy), 0);
        expect(await ids(), hasLength(5));
      },
    );

    test('dada la limpieza repetida (reentrada), la segunda no borra más ni falla', () async {
      await sembrarTres();
      await hora.registrar(hoy);
      expect(await limpiar(relojEquipo: hoy), 2);
      expect(await limpiar(relojEquipo: hoy), 0);
      expect(await ids(), ['activa', 'reciente', 'visita-vieja']);
    });

    test('dadas 40 horas registradas a la vez y desordenadas, queda la más alta', () async {
      final horas = [for (var i = 0; i < 40; i++) haceDias(i)]..shuffle();
      await Future.wait([for (final h in horas) hora.registrar(h)]);
      expect(await hora.ultima(), haceDias(0));
    });

    test(
      'dada una hora del servidor en otra zona horaria, se guarda y se compara en UTC',
      () async {
        await hora.registrar(DateTime.parse('2026-11-03T12:00:00-03:00'));
        expect(await hora.ultima(), DateTime.utc(2026, 11, 3, 15));
      },
    );
  });

  group('la cadena transporte real → decorador → base', () {
    test('dado un pull que contesta server_time, queda anotada', () async {
      final t = TransporteQueAnotaLaHora(
        rpc(
          (_) => json({
            'server_time': '2026-11-03T15:00:00Z',
            'watermark': 'w1',
            'has_more': false,
            'rows': <String, Object?>{},
          }),
        ),
        hora,
      );
      await t.pull(entities: const ['nota']);
      expect(await hora.ultima(), hoy);
    });

    test('dado un push que contesta server_time, queda anotada', () async {
      final t = TransporteQueAnotaLaHora(
        rpc((_) => json({'server_time': '2026-11-03T15:00:00Z', 'results': <Object?>[]})),
        hora,
      );
      await t.push(loteDe(1));
      expect(await hora.ultima(), hoy);
    });

    test('dado un push que el servidor rechaza (500), no anota nada y la falla sube', () async {
      final t = TransporteQueAnotaLaHora(rpc((_) => json({'message': 'boom'}, 500)), hora);
      await expectLater(t.push(loteDe(1)), throwsA(isA<TransportFailure>()));
      expect(await hora.ultima(), isNull);
    });

    test(
      'dado un lote con un job que el servidor rechaza por grande (CS003), no anota la hora del equipo',
      () async {
        var llamadas = 0;
        final t = TransporteQueAnotaLaHora(
          rpc((_) {
            llamadas++;
            return json({'code': 'CS003', 'message': 'lote demasiado grande'}, 413);
          }),
          hora,
        );
        final r = await t.push(loteDe(3));
        expect(llamadas, greaterThan(1), reason: 'parte el lote hasta llegar a jobs sueltos');
        expect(r.results.every((j) => j.code == 'CS003'), isTrue);
        expect(await hora.ultima(), isNull, reason: 'esa server_time la armó el cliente');
      },
    );

    test(
      'dado un lote partido donde la 2.ª mitad entra y un job suelto de la 1.ª no, no anota (conservador)',
      () async {
        var n = 0;
        final t = TransporteQueAnotaLaHora(
          rpc((_) {
            n++;
            return n == 1
                ? json({'code': 'CS003', 'message': 'grande'}, 413)
                : n == 2
                ? json({'code': 'CS003', 'message': 'grande'}, 413)
                : json({'server_time': '2026-11-03T15:00:00Z', 'results': <Object?>[]});
          }),
          hora,
        );
        await t.push(loteDe(2));
        // Lo que importa: nunca una hora más alta que la real del servidor.
        final ultima = await hora.ultima();
        expect(ultima == null || !ultima.isAfter(hoy), isTrue);
      },
    );

    test(
      'dado un servidor que contesta el pull SIN server_time, la hora del equipo no se anota como del servidor',
      () async {
        final t = TransporteQueAnotaLaHora(
          rpc((_) => json({'watermark': 'w1', 'has_more': false, 'rows': <String, Object?>{}})),
          hora,
        );
        await t.pull(entities: const ['nota']);
        expect(
          await hora.ultima(),
          isNull,
          reason:
              '`pullResponseFromJson` rellena `serverTime` con `DateTime.now()` si falta o es ilegible',
        );
      },
      // skip: QA #612 — `_fecha` (wire.dart) inventa DateTime.now() y el decorador lo anota como del servidor.
      skip: !_verHallazgos,
    );

    test(
      'dado un servidor que contesta el push con server_time ilegible, no se anota la hora del equipo',
      () async {
        final t = TransporteQueAnotaLaHora(
          rpc((_) => json({'server_time': 'ayer a la tarde', 'results': <Object?>[]})),
          hora,
        );
        await t.push(loteDe(1));
        expect(await hora.ultima(), isNull);
      },
      // skip: QA #612 — mismo hueco que el pull: `_fecha` rellena con el reloj del equipo.
      skip: !_verHallazgos,
    );
  });

  group('privacidad y fallas', () {
    test(
      'dada una falla al guardar la hora, la sync sigue y el log solo lleva el tipo del error',
      () async {
        await db.customStatement('DROP TABLE sync_meta');
        await hora.registrar(hoy);
        final texto = salida.lineas.join('\n');
        expect(texto, contains('HORA_SERVIDOR_GUARDAR_FAIL'));
        expect(texto, isNot(contains('2026-11-03')), reason: 'ni la hora ni el SQL en el log');
        expect(texto.toLowerCase(), isNot(contains('sync_meta')));
      },
    );

    test('dada una falla al leer la hora, la limpieza no borra nada y no explota', () async {
      await sembrarTres();
      await db.customStatement('DROP TABLE sync_meta');
      final caso = LimpiarNotasBorradasUseCase(
        LimpiezaNotasBorradasRepositoryImpl(
          NotasBorradasLocalDataSourceDrift(db),
          logger: loggerMudo(),
        ),
        ahora: () async => hoy,
        horaDelServidor: hora.ultima,
      );
      final r = await caso(const NoParams());
      expect(r.isLeft(), isTrue, reason: 'falla de lectura = falla visible, no borrado a ciegas');
      expect(await ids(), hasLength(5));
    });

    test('el toString del decorador y de la hora no llevan datos de la sesión', () {
      final t = TransporteQueAnotaLaHora(rpc((_) => json({})), hora);
      expect('$t$hora', isNot(contains('jwt')));
      expect('$t$hora', isNot(contains('anon')));
      expect('$t$hora', isNot(contains(_sobre.deviceId)));
    });
  });
}
