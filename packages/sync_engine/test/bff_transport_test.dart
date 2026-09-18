// El adaptador HTTP, probado en la VM con un MockClient: sin BFF levantado.
//
// Lo que se verifica es la traducción en las dos direcciones — qué se manda por
// el cable y cómo se interpreta lo que vuelve — contra
// docs/formato-de-cable.md.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

final _base = Uri.parse('https://bff.colportaje.test/');

const _sobre = ClientEnvelope(
  deviceId: '018f2c4e-6b7d-7a11-9f3c-000000000001',
  appVersion: '1.4.2',
);

BffTransport _transporte(
  Future<http.Response> Function(http.Request) responder, {
  String? jwt = 'jwt-de-prueba',
}) =>
    BffTransport(
      baseUrl: _base,
      token: () async => jwt,
      device: _sobre,
      client: MockClient(responder),
    );

http.Response _json(Object cuerpo,
        {int status = 200, Map<String, String>? headers}) =>
    http.Response(jsonEncode(cuerpo), status, headers: {
      'content-type': 'application/json; charset=utf-8',
      ...?headers,
    });

SyncJob _job({
  String opId = 'op-1',
  Op op = Op.insert,
  int? syncVersion,
}) =>
    SyncJob(
      clientOpId: opId,
      entity: 'venta',
      op: op,
      payload: const {'id': 'v-1', 'total': '1200.00'},
      syncVersion: syncVersion,
      createdAt: DateTime.utc(2026, 11, 13, 7, 0),
    );

void main() {
  group('push — lo que sale', () {
    test('manda el sobre con la forma acordada y el Bearer', () async {
      late http.Request visto;
      final t = _transporte((req) async {
        visto = req;
        return _json(
            {'server_time': '2026-11-13T08:00:00.000Z', 'results': []});
      });

      await t.push(PushBatch([_job(op: Op.update, syncVersion: 2)]));

      expect(visto.method, 'POST');
      expect(visto.url.path, '/sync/push');
      expect(visto.headers['Authorization'], 'Bearer jwt-de-prueba');

      final cuerpo = jsonDecode(visto.body) as Map<String, Object?>;
      final job = (cuerpo['jobs']! as List).single as Map<String, Object?>;
      expect(job['client_op_id'], 'op-1');
      expect(job['entity'], 'venta');
      expect(job['op'], 'update');
      expect(job['sync_version'], 2);
      expect((job['payload']! as Map)['total'], '1200.00',
          reason: 'el decimal viaja como String, nunca como número');
    });

    test('el sobre de §5.3 viaja en el cuerpo', () async {
      late http.Request visto;
      final t = _transporte((req) async {
        visto = req;
        return _json({'results': []});
      });

      await t.push(PushBatch([_job()]));

      final device = (jsonDecode(visto.body) as Map)['device'] as Map;
      expect(device['device_id'], _sobre.deviceId);
      expect(device['app_version'], '1.4.2');
      expect(device['schema_version'], kWireSchemaVersion,
          reason: 'sin esto el BFF no puede responder 426 a una app vieja');
    });

    test('sin sesión no manda Authorization en vez de mandar "Bearer null"',
        () async {
      late http.Request visto;
      final t = _transporte((req) async {
        visto = req;
        return _json({'results': []});
      }, jwt: null);

      await t.push(PushBatch([_job()]));
      expect(visto.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('push — lo que vuelve', () {
    test('traduce los cuatro outcomes', () async {
      final t = _transporte((_) async => _json({
            'server_time': '2026-11-13T08:00:00.000Z',
            'results': [
              {'client_op_id': 'a', 'outcome': 'accepted', 'sync_version': 1},
              {'client_op_id': 'b', 'outcome': 'duplicate'},
              {
                'client_op_id': 'c',
                'outcome': 'conflict',
                'sync_version': 3,
                'server_row': {'id': 'v-1', 'total': '9999.00'},
              },
              {
                'client_op_id': 'd',
                'outcome': 'invalid',
                'code': 'PRODUCTO_INEXISTENTE',
                'message': 'pk 812',
              },
            ],
          }));

      final r = await t.push(PushBatch([_job()]));

      expect(r.serverTime, DateTime.utc(2026, 11, 13, 8));
      expect(r.results.map((x) => x.outcome), [
        JobOutcome.accepted,
        JobOutcome.duplicate,
        JobOutcome.conflict,
        JobOutcome.invalid,
      ]);
      expect(r.byOutcome(JobOutcome.conflict).single.serverRow!['total'],
          '9999.00');
      expect(
          r.byOutcome(JobOutcome.invalid).single.code, 'PRODUCTO_INEXISTENTE');
      expect(r.settled, ['a', 'b'],
          reason: 'duplicate es éxito: sale de la cola igual que accepted');
    });

    test('un outcome desconocido no se toma por bueno', () async {
      final t = _transporte((_) async => _json({
            'results': [
              {'client_op_id': 'a', 'outcome': 'lo_que_sea'}
            ],
          }));

      final r = await t.push(PushBatch([_job()]));
      expect(r.results.single.outcome, JobOutcome.invalid,
          reason: 'tratarlo como aceptado borraría un job que nunca subió');
    });
  });

  group('pull', () {
    test('arma la query con entidades, watermark y limit', () async {
      late http.Request visto;
      final t = _transporte((req) async {
        visto = req;
        return _json({'watermark': 'w-2', 'has_more': false, 'rows': {}});
      });

      await t.pull(
          entities: const ['venta', 'producto'], watermark: 'w-1', limit: 500);

      expect(visto.url.path, '/sync/pull');
      expect(visto.url.queryParameters['entities'], 'venta,producto');
      expect(visto.url.queryParameters['watermark'], 'w-1');
      expect(visto.url.queryParameters['limit'], '500');
    });

    test('la primera sync va sin watermark', () async {
      late http.Request visto;
      final t = _transporte((req) async {
        visto = req;
        return _json({'watermark': 'w-1', 'rows': {}});
      });

      await t.pull(entities: const ['producto']);
      expect(visto.url.queryParameters.containsKey('watermark'), isFalse);
    });

    test('parsea las filas y hay_mas', () async {
      final t = _transporte((_) async => _json({
            'server_time': '2026-11-13T08:00:00.000Z',
            'watermark': 'w-9',
            'has_more': true,
            'rows': {
              'producto': [
                {'id': 'p-1', 'nombre': 'El Camino a Cristo', 'sync_version': 4}
              ],
            },
          }));

      final d = await t.pull(entities: const ['producto']);
      expect(d.watermark, 'w-9');
      expect(d.hasMore, isTrue);
      expect(d.rows['producto']!.single['nombre'], 'El Camino a Cristo');
    });

    test('si el BFF no manda watermark, se conserva el que había', () async {
      final t = _transporte((_) async => _json({'rows': {}}));
      final d = await t.pull(entities: const ['producto'], watermark: 'w-4');
      expect(d.watermark, 'w-4',
          reason: 'inventar uno acá sería adelantar el cursor sin datos');
    });
  });

  group('el sobre en las dos direcciones (F4)', () {
    test('el pull lo lleva en el query: no hay cuerpo donde meterlo', () async {
      late http.Request visto;
      final t = _transporte((req) async {
        visto = req;
        return _json({'rows': {}});
      });

      await t.pull(entities: const ['producto']);

      final q = visto.url.queryParameters;
      expect(q['device_id'], _sobre.deviceId);
      expect(q['app_version'], '1.4.2');
      expect(q['schema_version'], '$kWireSchemaVersion');
      expect(q['entities'], 'producto',
          reason: 'el sobre se suma a los parámetros, no los pisa');
    });

    test('ida y vuelta por el codec, en las dos formas', () {
      const id = '018f2c4e-6b7d-7a11-9f3c-8e2d5b6a7c90';
      const sobre =
          ClientEnvelope(deviceId: id, appVersion: '2.0.0', schemaVersion: 7);

      expect(envelopeFromJson(envelopeToJson(sobre))!.schemaVersion, 7);
      expect(envelopeFromQuery(envelopeToQuery(sobre))!.deviceId, id);
      expect(envelopeFromQuery(envelopeToQuery(sobre))!.appVersion, '2.0.0');
    });

    test('un device_id que no es UUID es 400, no un 500 de Postgres', () {
      // Del otro lado entra como `uuid`. Un texto que no castea saldría como
      // 5xx, el motor lo tomaría como transitorio y ese dispositivo
      // reintentaría para siempre sin subir nada.
      expect(
        () => envelopeFromJson(
            const {'device_id': 'el-telefono-de-juan', 'schema_version': 1}),
        throwsFormatException,
      );
      expect(
        () => envelopeFromQuery(
            const {'device_id': '123', 'schema_version': '1'}),
        throwsFormatException,
      );
    });

    test('sin sobre es null —app vieja, no cliente roto—; roto es excepción',
        () {
      expect(envelopeFromJson(null), isNull);
      expect(envelopeFromQuery(const {}), isNull);

      expect(() => envelopeFromJson(const {'app_version': '1.0.0'}),
          throwsFormatException,
          reason: 'un sobre presente sin device_id es un cliente roto');
      expect(
          () => envelopeFromQuery(
              const {'device_id': 'd-1', 'schema_version': 'ayer'}),
          throwsFormatException);
    });

    test('un push sin app_version igual sincroniza', () {
      final pedido = pushRequestFromJson({
        'device': {
          'device_id': '018f2c4e-6b7d-7a11-9f3c-8e2d5b6a7c90',
          'schema_version': 1,
        },
        'jobs': const <Object?>[],
      });

      expect(pedido.device!.appVersion, '',
          reason: 'la telemetría no puede frenar una venta');
    });
  });

  group('errores (§5.1)', () {
    Future<TransportFailure> falla(http.Response respuesta) async {
      final t = _transporte((_) async => respuesta);
      try {
        await t.push(PushBatch([_job()]));
        fail('tenía que lanzar');
      } on TransportFailure catch (f) {
        return f;
      }
    }

    test('422 es payload, con el código del cuerpo', () async {
      final f = await falla(_json(
          {'code': 'VENTA_SIN_ITEMS', 'message': 'sin items'},
          status: 422));
      expect(f.kind, FailureKind.payload);
      expect(f.code, 'VENTA_SIN_ITEMS');
      expect(f.message, 'sin items');
    });

    test('500 es transitorio', () async {
      expect((await falla(_json({}, status: 500))).kind, FailureKind.transient);
    });

    test('429 trae el Retry-After en segundos', () async {
      final f =
          await falla(_json({}, status: 429, headers: {'retry-after': '30'}));
      expect(f.kind, FailureKind.transient);
      expect(f.retryAfter, const Duration(seconds: 30));
    });

    test('426 es transitorio: la app está vieja, la venta no', () async {
      final f = await falla(_json(
          {'code': 'SCHEMA_VERSION_VIEJA', 'message': 'actualizá la app'},
          status: 426));

      expect(f.kind, FailureKind.transient,
          reason: 'mandar a INVALID una venta buena porque la app quedó vieja '
              'la esconde en la cola de error en vez de subirla sola cuando '
              'el colportor actualiza');
      expect(f.code, 'SCHEMA_VERSION_VIEJA',
          reason: 'la UI necesita distinguirlo de "sin red" para poder decir '
              'qué hacer');
    });

    test('401 es transitorio: el refresh es de la app (§10)', () async {
      expect((await falla(_json({}, status: 401))).kind, FailureKind.transient);
    });

    test('un error sin cuerpo JSON igual se clasifica por el status', () async {
      final f = await falla(http.Response('<html>502</html>', 502));
      expect(f.kind, FailureKind.transient);
      expect(f.code, 'HTTP_502');
    });

    test('una respuesta 200 ilegible es transitoria, no INVALID', () async {
      final f = await falla(http.Response('esto no es json', 200));
      expect(f.kind, FailureKind.transient);
      expect(f.code, 'RESPUESTA_ILEGIBLE',
          reason: 'un bug del servidor no puede invalidar una venta buena');
    });

    test('un timeout es transitorio', () async {
      final t = BffTransport(
        baseUrl: _base,
        token: () async => 'jwt',
        device: _sobre,
        timeout: const Duration(milliseconds: 20),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return _json({});
        }),
      );

      await expectLater(
        t.push(PushBatch([_job()])),
        throwsA(isA<TransportFailure>()
            .having((f) => f.kind, 'kind', FailureKind.transient)
            .having((f) => f.code, 'code', 'TIMEOUT')),
      );
    });

    test('sin red es transitorio, no una excepción de http', () async {
      final t = _transporte((_) async => throw http.ClientException('sin red'));
      await expectLater(
        t.pull(entities: const ['producto']),
        throwsA(isA<TransportFailure>()
            .having((f) => f.kind, 'kind', FailureKind.transient)),
      );
    });
  });

  group('integración', _integracion);
}

// ---------------------------------------------------------------------------
// El motor entero sobre el adaptador real, sin BFF levantado.
// ---------------------------------------------------------------------------

void _integracion() {
  test('el motor sube una venta por HTTP y la cierra', () async {
    final pedidos = <http.Request>[];
    final transporte = BffTransport(
      baseUrl: _base,
      token: () async => 'jwt',
      device: _sobre,
      client: MockClient((req) async {
        pedidos.add(req);
        if (req.url.path == '/sync/push') {
          final jobs = (jsonDecode(req.body) as Map)['jobs'] as List;
          return _json({
            'server_time': '2026-11-13T08:00:00.000Z',
            'results': [
              for (final j in jobs)
                {
                  'client_op_id': (j as Map)['client_op_id'],
                  'outcome': 'accepted',
                  'sync_version': 1,
                }
            ],
          });
        }
        return _json({
          'watermark': 'w-1',
          'has_more': false,
          'rows': {
            'producto': [
              {'id': 'p-1', 'nombre': 'El Deseado', 'sync_version': 1}
            ],
          },
        });
      }),
    );

    final jobs = InMemoryJobStore();
    final store = InMemoryLocalStore();
    final motor = SyncEngine(
      specs: SpecRegistry([
        SyncSpec.push('venta'),
        SyncSpec.pull('producto'),
        SyncSpec.local('persona'),
      ], allEntities: {
        'venta',
        'producto',
        'persona'
      }),
      transport: transporte,
      jobs: jobs,
      store: store,
    );

    final id = await motor.stage(
        'venta', Op.insert, {'id': 'v-1', 'total': '1200.00'},
        clientOpId: 'op-1');
    final r = await motor.syncNow();

    expect(r.ok, isTrue);
    expect(r.pushed, 1);
    expect(jobs.byId(id).state, JobState.done);
    expect(store.rows['producto']!.single['nombre'], 'El Deseado');
    expect(store.watermarks['replica'], 'w-1');
    expect(pedidos.map((p) => p.url.path), ['/sync/push', '/sync/pull']);

    await motor.dispose();
  });
}
