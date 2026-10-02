// El transporte RPC, probado en la VM con un MockClient: sin Supabase levantado.
//
// Se verifica contra el contrato §6.1 (0.9.10) y el header de backend-supabase
// 0025: qué se manda por el cable, cómo se clasifica cada rechazo del lote por su
// `code` y no por el status, cómo vuelve cada resultado por job, que el watermark
// va y vuelve como string sin tocarlo, y que `CS003` parte el lote.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:sync_engine/testing.dart';
import 'package:test/test.dart';

final _proyecto = Uri.parse('https://proyecto.supabase.test');

const _anonKey = 'anon-key-de-prueba';

const _sobre = ClientEnvelope(
  deviceId: '018f2c4e-6b7d-7a11-9f3c-000000000001',
  appVersion: '1.4.2',
);

SupabaseRpcTransport _transporte(
  Future<http.Response> Function(http.Request) responder, {
  String? jwt = 'jwt-de-prueba',
  Uri? proyecto,
  Duration timeout = const Duration(seconds: 30),
}) => SupabaseRpcTransport(
  projectUrl: proyecto ?? _proyecto,
  anonKey: _anonKey,
  token: () async => jwt,
  device: _sobre,
  client: MockClient(responder),
  timeout: timeout,
);

http.Response _json(
  Object? cuerpo, {
  int status = 200,
  Map<String, String>? headers,
}) => http.Response(
  jsonEncode(cuerpo),
  status,
  headers: {'content-type': 'application/json; charset=utf-8', ...?headers},
);

/// Un error de PostgREST: el SQLSTATE en `code`.
http.Response _errorPostgrest(
  int status,
  String code, [
  String message = 'rechazado',
]) => _json({
  'code': code,
  'message': message,
  'details': null,
  'hint': null,
}, status: status);

/// Lo que va adentro de `p_body`.
Map<String, Object?> _pBody(http.Request req) =>
    ((jsonDecode(req.body) as Map)['p_body'] as Map).cast<String, Object?>();

List<String> _opIds(http.Request req) => [
  for (final j in _pBody(req)['jobs']! as List)
    (j as Map)['client_op_id'] as String,
];

Future<http.Response> _aceptarTodoAsync(http.Request req) async =>
    _aceptarTodo(req);

/// Todos los jobs del pedido, aceptados.
http.Response _aceptarTodo(http.Request req) => _json({
  'server_time': '2026-10-05T08:00:00.000Z',
  'results': [
    for (final id in _opIds(req))
      {'client_op_id': id, 'outcome': 'accepted', 'sync_version': 1},
  ],
});

SyncJob _job(String opId, {Op op = Op.insert, int? syncVersion}) => SyncJob(
  clientOpId: opId,
  entity: 'venta',
  op: op,
  payload: {'id': 'v-$opId', 'total': '1200.00'},
  syncVersion: syncVersion,
  createdAt: DateTime.utc(2026, 10, 5, 7, 0),
);

void main() {
  group('lo que sale', () {
    test(
      'push: POST a rpc/sync_push con el codec envuelto en p_body',
      () async {
        late http.Request visto;
        final t = _transporte((req) async {
          visto = req;
          return _aceptarTodo(req);
        });
        final lote = PushBatch([_job('op-1', op: Op.update, syncVersion: 2)]);

        await t.push(lote);

        expect(visto.method, 'POST');
        expect(
          visto.url.toString(),
          'https://proyecto.supabase.test/rest/v1/rpc/sync_push',
        );
        expect(jsonDecode(visto.body), {
          'p_body': jsonDecode(jsonEncode(pushRequestToJson(lote, _sobre))),
        }, reason: 'el mismo JSON del codec, sin una segunda implementación');
        final job = (_pBody(visto)['jobs']! as List).single as Map;
        expect(
          (job['payload'] as Map)['total'],
          '1200.00',
          reason: 'el decimal viaja como String, nunca como número',
        );
      },
    );

    test(
      'pull: POST a rpc/sync_pull con entities como array y el sobre',
      () async {
        late http.Request visto;
        final t = _transporte((req) async {
          visto = req;
          return _json({'watermark': 'w', 'has_more': false, 'rows': {}});
        });

        await t.pull(
          entities: ['venta', 'producto'],
          watermark: 'w-0',
          limit: 500,
        );

        expect(visto.method, 'POST');
        expect(visto.url.path, '/rest/v1/rpc/sync_pull');
        expect(visto.url.query, isEmpty, reason: 'ya no va nada por el query');
        expect(_pBody(visto), {
          'device': {
            'device_id': _sobre.deviceId,
            'app_version': '1.4.2',
            'schema_version': kWireSchemaVersion,
          },
          'entities': ['venta', 'producto'],
          'watermark': 'w-0',
          'limit': 500,
        });
      },
    );

    test('pull: sin watermark ni limit no los manda', () async {
      late http.Request visto;
      final t = _transporte((req) async {
        visto = req;
        return _json({'watermark': 'w', 'has_more': false, 'rows': {}});
      });

      await t.pull(entities: ['producto']);

      expect(
        _pBody(visto).keys,
        unorderedEquals(['device', 'entities']),
        reason: 'sin watermark es una réplica desde cero',
      );
    });

    test('apikey siempre, y el JWT del colportor como Bearer', () async {
      late http.Request visto;
      final t = _transporte((req) async {
        visto = req;
        return _aceptarTodo(req);
      });

      await t.push(PushBatch([_job('op-1')]));

      expect(visto.headers['apikey'], _anonKey);
      expect(visto.headers['Authorization'], 'Bearer jwt-de-prueba');
      expect(visto.headers['Content-Type'], startsWith('application/json'));
    });

    test('sin sesión manda la apikey y ningún Authorization', () async {
      late http.Request visto;
      final t = _transporte((req) async {
        visto = req;
        return _aceptarTodo(req);
      }, jwt: null);

      await t.push(PushBatch([_job('op-1')]));

      expect(visto.headers['apikey'], _anonKey);
      expect(
        visto.headers.containsKey('Authorization'),
        isFalse,
        reason: 'ni "Bearer null" ni la anon key haciéndose pasar por JWT',
      );
    });

    test('un projectUrl con path sin barra final no pierde el path', () async {
      late http.Request visto;
      final t = _transporte((req) async {
        visto = req;
        return _aceptarTodo(req);
      }, proyecto: Uri.parse('http://127.0.0.1:54321/local'));

      await t.push(PushBatch([_job('op-1')]));

      expect(visto.url.path, '/local/rest/v1/rpc/sync_push');
    });
  });

  // §6.1, primera tabla: lo que rechaza el lote entero llega como error de la
  // llamada, y decide el `code`, no el status.
  group('rechazos del lote entero (§6.1)', () {
    const tabla = <(String, int, FailureKind)>[
      ('CS001', 400, FailureKind.payload),
      ('CS002', 400, FailureKind.transient),
      ('42501', 401, FailureKind.transient),
      ('42501', 403, FailureKind.transient),
      ('22023', 400, FailureKind.payload),
    ];

    for (final (code, status, kind) in tabla) {
      for (final llamada in ['push', 'pull']) {
        test('$code con $status → ${kind.name} ($llamada)', () async {
          final t = _transporte(
            (_) async => _errorPostgrest(status, code, 'motivo $code'),
          );

          final falla = await _fallaDe(
            llamada == 'push'
                ? t.push(PushBatch([_job('op-1')]))
                : t.pull(entities: ['venta']),
          );

          expect(falla.kind, kind);
          expect(
            falla.code,
            code,
            reason:
                'la UI distingue «actualizá la app» de «sin red» por '
                'el code',
          );
          expect(falla.status, status);
          expect(falla.message, 'motivo $code');
        });
      }
    }

    test('CS002 con el mismo status que CS001 no se clasifica igual', () {
      expect(kindForRpcError(400, 'CS001'), FailureKind.payload);
      expect(
        kindForRpcError(400, 'CS002'),
        FailureKind.transient,
        reason:
            'mandar a INVALID las ventas de una app vieja las dejaría '
            'varadas cuando se actualice',
      );
    });

    test('un code fuera de la tabla cae a la clasificación por status', () {
      expect(kindForRpcError(400, 'P0001'), FailureKind.payload);
      expect(
        kindForRpcError(401, 'PGRST301'),
        FailureKind.transient,
        reason: 'JWT vencido: espera el refresh (§10)',
      );
      expect(
        kindForRpcError(404, 'PGRST202'),
        FailureKind.transient,
        reason: 'la función todavía no está desplegada',
      );
      expect(kindForRpcError(503, 'HTTP_503'), FailureKind.transient);
    });

    test('429 respeta el Retry-After del gateway', () async {
      final t = _transporte(
        (_) async => _json(
          {'message': 'rate limit'},
          status: 429,
          headers: {'retry-after': '12'},
        ),
      );

      final falla = await _fallaDe(t.push(PushBatch([_job('op-1')])));

      expect(falla.kind, FailureKind.transient);
      expect(falla.retryAfter, const Duration(seconds: 12));
    });

    test('un 502 del gateway sin cuerpo JSON es transitorio', () async {
      final t = _transporte((_) async => http.Response('Bad Gateway', 502));

      final falla = await _fallaDe(t.pull(entities: ['venta']));

      expect(falla.kind, FailureKind.transient);
      expect(falla.code, 'HTTP_502');
    });

    test(
      'sin red: SIN_RED transitorio, sin excepciones de package:http',
      () async {
        final t = _transporte(
          (_) async => throw http.ClientException('Connection refused'),
        );

        final falla = await _fallaDe(t.push(PushBatch([_job('op-1')])));

        expect(falla.kind, FailureKind.transient);
        expect(falla.code, 'SIN_RED');
        expect(falla.status, isNull);
      },
    );

    test('timeout: TIMEOUT transitorio', () async {
      final t = _transporte(
        (_) => Completer<http.Response>().future,
        timeout: const Duration(milliseconds: 10),
      );

      final falla = await _fallaDe(t.push(PushBatch([_job('op-1')])));

      expect(falla.code, 'TIMEOUT');
      expect(falla.kind, FailureKind.transient);
    });

    test('un 200 que no es JSON es transitorio', () async {
      final t = _transporte((_) async => http.Response('<html>', 200));

      final falla = await _fallaDe(t.push(PushBatch([_job('op-1')])));

      expect(falla.code, 'RESPUESTA_ILEGIBLE');
      expect(falla.kind, FailureKind.transient);
    });
  });

  group('CS003: lote demasiado grande', () {
    test(
      'parte el lote por la mitad, en orden, y junta los resultados',
      () async {
        final pedidos = <List<String>>[];
        final t = _transporte((req) async {
          final ids = _opIds(req);
          pedidos.add(ids);
          if (ids.length > 2) return _errorPostgrest(400, 'CS003');
          return _aceptarTodo(req);
        });

        final r = await t.push(
          PushBatch([for (var i = 1; i <= 5; i++) _job('op-$i')]),
        );

        expect(pedidos, [
          ['op-1', 'op-2', 'op-3', 'op-4', 'op-5'],
          ['op-1', 'op-2'],
          ['op-3', 'op-4', 'op-5'],
          ['op-3'],
          ['op-4', 'op-5'],
        ], reason: 'las partes suben en orden de creación (§5.5)');
        expect(r.results.map((x) => x.clientOpId), [
          'op-1',
          'op-2',
          'op-3',
          'op-4',
          'op-5',
        ]);
        expect(r.settled, hasLength(5));
      },
    );

    test(
      'un lote de un solo job que pasa el tope: ese job a invalid',
      () async {
        var llamadas = 0;
        final t = _transporte((req) async {
          llamadas++;
          return _errorPostgrest(400, 'CS003', 'el lote pasa 1 MB');
        });

        final r = await t.push(PushBatch([_job('op-gordo')]));

        expect(llamadas, 1);
        final res = r.results.single;
        expect(res.clientOpId, 'op-gordo');
        expect(res.outcome, JobOutcome.invalid);
        expect(res.code, 'CS003');
        expect(res.message, 'el lote pasa 1 MB');
      },
    );

    test('el job gordo va a invalid y el resto del lote entra', () async {
      final t = _transporte((req) async {
        final ids = _opIds(req);
        if (ids.contains('op-gordo')) return _errorPostgrest(400, 'CS003');
        return _aceptarTodo(req);
      });

      final r = await t.push(
        PushBatch([_job('op-1'), _job('op-gordo'), _job('op-3')]),
      );

      expect(
        {for (final x in r.results) x.clientOpId: x.outcome},
        {
          'op-1': JobOutcome.accepted,
          'op-gordo': JobOutcome.invalid,
          'op-3': JobOutcome.accepted,
        },
      );
    });

    test('si una parte falla por otra cosa, la falla sale entera', () async {
      final t = _transporte((req) async {
        final ids = _opIds(req);
        if (ids.length > 1) return _errorPostgrest(400, 'CS003');
        if (ids.single == 'op-2') return http.Response('', 503);
        return _aceptarTodo(req);
      });

      final falla = await _fallaDe(
        t.push(PushBatch([_job('op-1'), _job('op-2')])),
      );

      expect(
        falla.kind,
        FailureKind.transient,
        reason: 'el motor vuelve el lote a PENDING; op-1 vuelve duplicate',
      );
    });

    test(
      'de punta a punta: el motor deja DONE lo que entró e INVALID el gordo',
      () async {
        final a = _armarMotor((req) async {
          final ids = _opIds(req);
          if (ids.contains('op-gordo')) return _errorPostgrest(400, 'CS003');
          return _aceptarTodo(req);
        });

        await a.motor.stage('venta', Op.insert, {
          'id': 'v1',
        }, clientOpId: 'op-1');
        await a.motor.stage('venta', Op.insert, {
          'id': 'v2',
        }, clientOpId: 'op-gordo');
        await a.motor.stage('venta', Op.insert, {
          'id': 'v3',
        }, clientOpId: 'op-3');
        final salida = await a.motor.syncNow();

        expect(salida.failure, isNull);
        expect(a.estadoDe('op-1'), JobState.done);
        expect(a.estadoDe('op-3'), JobState.done);
        expect(a.estadoDe('op-gordo'), JobState.invalid);
        expect(a.jobDe('op-gordo').code, 'CS003');
        await a.motor.dispose();
      },
    );
  });

  // §6.1, segunda tabla: lo que se decide por job va en el cuerpo de un 200.
  group('resultados por job (§6.1)', () {
    test('el transporte trae cada fila de la tabla tal cual', () async {
      final t = _transporte(
        (_) async => _json({
          'server_time': '2026-10-05T08:00:00.000Z',
          'results': [
            {'client_op_id': 'a', 'outcome': 'accepted', 'sync_version': 1},
            {'client_op_id': 'b', 'outcome': 'duplicate'},
            {
              'client_op_id': 'c',
              'outcome': 'conflict',
              'sync_version': 3,
              'server_row': {'id': 'v-c', 'total': '9999.00'},
            },
            {
              'client_op_id': 'd',
              'outcome': 'conflict',
              'code': '23505',
              'constraint': 'ubicacion_direccion_unica',
              'message': 'Ya hay otra ubicación en Rivera 1234',
            },
            {
              'client_op_id': 'e',
              'outcome': 'conflict',
              'code': 'ESPERA_ALTA_EN_CONFLICTO',
              'depends_on': 'ubi-1',
              'message': 'cuelga de un alta en conflicto',
            },
            {'client_op_id': 'f', 'outcome': 'invalid', 'code': 'CG001'},
          ],
        }),
      );

      final r = await t.push(PushBatch([_job('a')]));
      final porId = {for (final x in r.results) x.clientOpId: x};

      expect(porId['a']!.outcome, JobOutcome.accepted);
      expect(porId['a']!.syncVersion, 1);
      expect(porId['b']!.outcome, JobOutcome.duplicate);
      expect(porId['c']!.outcome, JobOutcome.conflict);
      expect(porId['c']!.serverRow, {'id': 'v-c', 'total': '9999.00'});

      expect(porId['d']!.outcome, JobOutcome.conflict);
      expect(porId['d']!.code, '23505');
      expect(porId['d']!.constraint, 'ubicacion_direccion_unica');
      expect(porId['d']!.serverRow, isNull);

      expect(porId['e']!.outcome, JobOutcome.conflict);
      expect(porId['e']!.code, 'ESPERA_ALTA_EN_CONFLICTO');
      expect(porId['e']!.dependsOn, 'ubi-1');
      expect(porId['e']!.serverRow, isNull);

      expect(porId['f']!.outcome, JobOutcome.invalid);
      expect(porId['f']!.code, 'CG001');
    });

    test('constraint y depends_on van y vuelven por el codec', () {
      const original = JobResult(
        clientOpId: 'e',
        outcome: JobOutcome.conflict,
        code: 'ESPERA_ALTA_EN_CONFLICTO',
        constraint: 'ubicacion_direccion_unica',
        dependsOn: 'ubi-1',
      );
      final ida = pushResponseToJson(
        PushResult(serverTime: DateTime.utc(2026, 10, 5), results: [original]),
      );
      final vuelta = pushResponseFromJson(
        jsonDecode(jsonEncode(ida)) as Map<String, Object?>,
      ).results.single;

      expect(vuelta.constraint, original.constraint);
      expect(vuelta.dependsOn, original.dependsOn);
    });

    // De punta a punta, una fila de la tabla por test: qué estado deja el motor.
    Future<QueuedJob> correr(Map<String, Object?> resultado) async {
      final a = _armarMotor(
        (req) async => _json({
          'server_time': '2026-10-05T08:00:00.000Z',
          'results': [
            {'client_op_id': 'op-1', ...resultado},
          ],
        }),
      );
      await a.motor.stage('ubicacion', Op.insert, {
        'id': 'ubi-1',
      }, clientOpId: 'op-1');
      await a.motor.syncNow();
      await a.motor.dispose();
      return a.jobDe('op-1');
    }

    test('accepted → DONE', () async {
      final j = await correr({'outcome': 'accepted', 'sync_version': 1});
      expect(j.state, JobState.done);
    });

    test('duplicate → DONE', () async {
      final j = await correr({'outcome': 'duplicate'});
      expect(j.state, JobState.done);
    });

    test('conflict con server_row → LWW y DONE', () async {
      final a = _armarMotor(
        (req) async => _json({
          'server_time': '2026-10-05T08:00:00.000Z',
          'results': [
            {
              'client_op_id': 'op-1',
              'outcome': 'conflict',
              'sync_version': 3,
              'server_row': {'id': 'ubi-1', 'sync_version': 3},
            },
          ],
        }),
      );
      await a.motor.stage(
        'ubicacion',
        Op.update,
        {'id': 'ubi-1'},
        clientOpId: 'op-1',
        syncVersion: 2,
      );
      await a.motor.syncNow();
      await a.motor.dispose();

      expect(a.estadoDe('op-1'), JobState.done);
      expect(a.store.rows['ubicacion'], [
        {'id': 'ubi-1', 'sync_version': 3},
      ]);
    });

    test(
      'conflict 23505 ubicacion_direccion_unica → la fila queda y el job no '
      'se cierra',
      () async {
        final j = await correr({
          'outcome': 'conflict',
          'code': '23505',
          'constraint': 'ubicacion_direccion_unica',
        });
        expect(j.state, isNot(JobState.done));
      },
      skip:
          'Falta en el núcleo (#178): hoy todo conflict sin server_row '
          'termina DONE y el alta no se vuelve a subir.',
    );

    test(
      'conflict ESPERA_ALTA_EN_CONFLICTO → en espera, no DONE',
      () async {
        final j = await correr({
          'outcome': 'conflict',
          'code': 'ESPERA_ALTA_EN_CONFLICTO',
          'depends_on': 'ubi-0',
        });
        expect(j.state, isNot(JobState.done));
      },
      skip:
          'Falta en el núcleo (#178): el estado «en espera» de §5.1 no '
          'existe en JobState; hoy la venta queda DONE sin haber subido.',
    );

    const invalidos = [
      'CG001',
      'UB001',
      'UB002',
      '42501',
      'FILA_INEXISTENTE',
      '23503',
      '22007',
      'ENTIDAD_DESCONOCIDA',
      'ENTIDAD_DE_SOLO_LECTURA',
      'OP_INVALIDA',
      'OP_ID_REQUERIDO',
      'PAYLOAD_VACIO',
      'PK_FALTANTE',
    ];
    for (final code in invalidos) {
      test('invalid $code → INVALID con su code', () async {
        final j = await correr({
          'outcome': 'invalid',
          'code': code,
          'message': 'motivo',
        });
        expect(j.state, JobState.invalid);
        expect(j.code, code, reason: 'la app elige el aviso por el code');
      });
    }
  });

  group('rechazos del lote, de punta a punta', () {
    test('CS001: los jobs del lote a INVALID', () async {
      final a = _armarMotor((_) async => _errorPostgrest(400, 'CS001'));
      await a.motor.stage('venta', Op.insert, {'id': 'v1'}, clientOpId: 'op-1');
      await a.motor.syncNow();
      await a.motor.dispose();

      expect(a.estadoDe('op-1'), JobState.invalid);
      expect(a.jobDe('op-1').code, 'CS001');
    });

    test(
      'CS002: los jobs esperan en PENDING y el ciclo informa el code',
      () async {
        final a = _armarMotor((_) async => _errorPostgrest(400, 'CS002'));
        await a.motor.stage('venta', Op.insert, {
          'id': 'v1',
        }, clientOpId: 'op-1');
        final salida = await a.motor.syncNow();
        await a.motor.dispose();

        expect(a.estadoDe('op-1'), JobState.pending);
        expect(salida.failure?.code, 'CS002');
      },
    );

    test('42501: los jobs esperan el refresh en PENDING', () async {
      final a = _armarMotor((_) async => _errorPostgrest(403, '42501'));
      await a.motor.stage('venta', Op.insert, {'id': 'v1'}, clientOpId: 'op-1');
      await a.motor.syncNow();
      await a.motor.dispose();

      expect(a.estadoDe('op-1'), JobState.pending);
    });

    test('22023: los jobs del lote a INVALID', () async {
      final a = _armarMotor((_) async => _errorPostgrest(400, '22023'));
      await a.motor.stage('venta', Op.insert, {'id': 'v1'}, clientOpId: 'op-1');
      await a.motor.syncNow();
      await a.motor.dispose();

      expect(a.estadoDe('op-1'), JobState.invalid);
    });
  });

  group('watermark: string opaco de ida y vuelta', () {
    // El de sync.pull() serializado: JSON adentro de un string, con comillas y
    // un carácter fuera de ASCII. Tiene que volver idéntico, byte por byte.
    const w1 = '{"venta": {"sv": 12, "id": "ñ-018f"}, "ts": "2026-10-05"}';
    const w2 = '{"venta": {"sv": 40, "id": "ñ-0190"}, "ts": "2026-10-05"}';

    test('el que devolvió un pull es el que manda el siguiente', () async {
      final mandados = <Object?>[];
      final t = _transporte((req) async {
        mandados.add(_pBody(req)['watermark']);
        return _json({
          'server_time': '2026-10-05T08:00:00.000Z',
          'watermark': mandados.length == 1 ? w1 : w2,
          'has_more': false,
          'rows': {},
        });
      });

      final primero = await t.pull(entities: ['venta']);
      final segundo = await t.pull(
        entities: ['venta'],
        watermark: primero.watermark,
      );

      expect(primero.watermark, w1);
      expect(mandados, [null, w1]);
      expect(segundo.watermark, w2);
    });

    test(
      'de punta a punta: el motor lo guarda y lo devuelve tal cual',
      () async {
        final mandados = <Object?>[];
        final a = _armarMotor(
          _aceptarTodoAsync,
          pull: (req) async {
            final cuerpo = _pBody(req);
            if (!(cuerpo['entities']! as List).contains('producto')) {
              return _json({'watermark': 'm', 'has_more': false, 'rows': {}});
            }
            mandados.add(cuerpo['watermark']);
            return _json({
              'server_time': '2026-10-05T08:00:00.000Z',
              'watermark': w1,
              'has_more': false,
              'rows': {
                'producto': [
                  {'id': 'p1'},
                ],
              },
            });
          },
        );

        await a.motor.syncNow();
        expect(a.store.watermarks.values, contains(w1));
        await a.motor.syncNow();
        await a.motor.dispose();

        expect(mandados, [null, w1]);
      },
    );

    test('un watermark que no es string es RESPUESTA_ILEGIBLE', () async {
      final t = _transporte(
        (_) async => _json({
          'watermark': {'venta': 12},
          'has_more': false,
          'rows': {},
        }),
      );

      final falla = await _fallaDe(t.pull(entities: ['venta']));

      expect(falla.code, 'RESPUESTA_ILEGIBLE');
      expect(
        falla.kind,
        FailureKind.transient,
        reason: 'no se adelanta el cursor con algo que no se puede devolver',
      );
    });

    test('sin watermark en la respuesta conserva el anterior', () async {
      final t = _transporte(
        (_) async => _json({'has_more': false, 'rows': {}}),
      );

      final d = await t.pull(entities: ['venta'], watermark: w1);

      expect(d.watermark, w1);
    });
  });
}

Future<TransportFailure> _fallaDe(Future<Object?> llamada) async {
  try {
    await llamada;
  } on TransportFailure catch (f) {
    return f;
  }
  fail('se esperaba TransportFailure');
}

({
  SyncEngine motor,
  InMemoryJobStore jobs,
  InMemoryLocalStore store,
  JobState Function(String) estadoDe,
  QueuedJob Function(String) jobDe,
})
_armarMotor(
  Future<http.Response> Function(http.Request) push, {
  Future<http.Response> Function(http.Request)? pull,
}) {
  final jobs = InMemoryJobStore();
  final store = InMemoryLocalStore();
  final transporte = _transporte((req) async {
    if (req.url.path.endsWith('/sync_push')) return push(req);
    // Sin handler de pull, el servidor no tiene nada nuevo que bajar.
    return pull?.call(req) ??
        _json({'watermark': 'w', 'has_more': false, 'rows': {}});
  });

  QueuedJob jobDe(String opId) =>
      jobs.all.firstWhere((q) => q.job.clientOpId == opId);

  return (
    motor: SyncEngine(
      specs: SpecRegistry(
        [
          SyncSpec.push('venta'),
          SyncSpec.push('ubicacion', alsoPull: true),
          SyncSpec.pull('producto'),
        ],
        allEntities: {'venta', 'ubicacion', 'producto'},
      ),
      transport: transporte,
      jobs: jobs,
      store: store,
      connectivity: FakeConnectivityPort(),
    ),
    jobs: jobs,
    store: store,
    estadoDe: (opId) => jobDe(opId).state,
    jobDe: jobDe,
  );
}
