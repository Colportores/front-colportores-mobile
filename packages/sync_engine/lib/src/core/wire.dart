// El formato de cable, en un solo lugar (docs/formato-de-cable.md).
//
// Del lado del motor lo usan `SupabaseRpcTransport` (ADR-013: las funciones de
// entrada `public.sync_push` y `public.sync_pull` reciben este mismo JSON como
// `p_body`) y `BffTransport`. Del otro lado, `sync.validar_sobre()` sigue a
// [envelopeFromJson] regla por regla (backend-supabase 0025): la definición del
// mensaje sigue siendo una sola, este archivo y docs/formato-de-cable.md.
//
// Es Dart puro y no toca HTTP: por eso vive en core/ y no en adapters/.

import 'model.dart';

// --- el sobre (§5.3) --------------------------------------------------------

/// Va en el cuerpo del push y del pull (en el query del pull de
/// `BffTransport`), pero es el mismo sobre y se arma en un solo lugar: es lo
/// único que hace que las dos rutas no puedan discrepar en cómo se llama un
/// campo.
Map<String, Object?> envelopeToJson(ClientEnvelope sobre) => {
      'device_id': sobre.deviceId,
      'app_version': sobre.appVersion,
      'schema_version': sobre.schemaVersion,
    };

/// `null` cuando **no vino sobre**, que no es lo mismo que un sobre roto.
///
/// Un cliente sin sobre es anterior a v1.0 del cable, y eso lo resuelve el BFF
/// con un `426` —"actualizá"—, no con un `400`. Decirle "payload inválido" a una
/// app vieja manda a `INVALID` ventas que están perfectas y que subirían solas
/// apenas se actualice.
///
/// Un sobre **presente y mal formado** sí es [FormatException]: eso no es una
/// app vieja, es un cliente roto.
ClientEnvelope? envelopeFromJson(Object? valor) {
  if (valor == null) return null;
  final j = _mapa(valor, 'device');

  final appVersion = j['app_version'];
  final schemaVersion = j['schema_version'];
  if (schemaVersion is! int) {
    throw const FormatException('schema_version tiene que ser un entero');
  }

  return ClientEnvelope(
    deviceId: _deviceId(j['device_id']),
    // La versión de la app no decide nada: si falta, se registra vacía y el
    // ciclo sigue. Cortar una sync por un campo de telemetría sería cambiar
    // ventas por una métrica.
    appVersion: appVersion is String ? appVersion : '',
    schemaVersion: schemaVersion,
  );
}

/// El `device_id` tiene que ser un UUID.
///
/// No es formalismo: del otro lado entra a Postgres como `uuid`, y un texto que
/// no castea sale como `5xx`. El motor clasifica `5xx` como transitorio, así
/// que un dispositivo con un id mal formado reintentaría **para siempre** y su
/// cola no volvería a subir nunca. Rechazarlo acá lo convierte en un `400`, que
/// es lo que es: un cliente que no cumple.
final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

String _deviceId(Object? valor) {
  if (valor is! String || !_uuid.hasMatch(valor)) {
    throw FormatException('device_id tiene que ser un UUID, no $valor');
  }
  return valor;
}

/// El mismo sobre, como parámetros de query. El pull es un `GET`: no hay cuerpo
/// donde meterlo.
Map<String, String> envelopeToQuery(ClientEnvelope sobre) => {
      'device_id': sobre.deviceId,
      'app_version': sobre.appVersion,
      'schema_version': '${sobre.schemaVersion}',
    };

/// Contraparte de [envelopeToQuery]. Mismas reglas que [envelopeFromJson]:
/// ausente es `null` (app vieja → `426`), presente y roto es [FormatException].
ClientEnvelope? envelopeFromQuery(Map<String, String> q) {
  final schemaVersion = q['schema_version'];
  final deviceId = q['device_id'];
  if (schemaVersion == null && deviceId == null) return null;

  final version = int.tryParse(schemaVersion ?? '');
  if (version == null) {
    throw const FormatException('schema_version tiene que ser un entero');
  }

  return ClientEnvelope(
    deviceId: _deviceId(deviceId),
    appVersion: q['app_version'] ?? '',
    schemaVersion: version,
  );
}

// --- POST /sync/push --------------------------------------------------------

/// Los jobs solos, sin el sobre. Lo usa el BFF para reenviar a `sync.push` lo
/// que ya validó.
List<Object?> jobsToJson(PushBatch batch) => [
      for (final job in batch.jobs)
        {
          'client_op_id': job.clientOpId,
          'entity': job.entity,
          'op': job.op.name,
          'sync_version': job.syncVersion,
          'payload': job.payload,
        },
    ];

Map<String, Object?> pushRequestToJson(
  PushBatch batch,
  ClientEnvelope sobre,
) => {
      'device': envelopeToJson(sobre),
      'jobs': jobsToJson(batch),
    };

/// Un push tal como lo recibe el BFF: los jobs y quién los manda.
class PushRequest {
  const PushRequest({required this.batch, required this.device});

  final PushBatch batch;

  /// `null` si el cliente no mandó sobre: ver [envelopeFromJson].
  final ClientEnvelope? device;
}

/// Lo que el BFF recibe. Lanza [FormatException] si el cuerpo no tiene la
/// forma acordada: el servidor responde `400` y el motor lo clasifica como
/// error de payload, que es lo correcto porque reintentarlo daría lo mismo.
PushRequest pushRequestFromJson(Map<String, Object?> json) {
  final crudos = json['jobs'];
  if (crudos is! List) {
    throw const FormatException('falta "jobs" o no es una lista');
  }
  return PushRequest(
    batch: PushBatch([
      for (final crudo in crudos) _jobFromJson(_mapa(crudo, 'job')),
    ]),
    device: envelopeFromJson(json['device']),
  );
}

SyncJob _jobFromJson(Map<String, Object?> j) {
  final opId = j['client_op_id'];
  final entity = j['entity'];
  if (opId is! String || entity is! String) {
    throw const FormatException('el job necesita client_op_id y entity');
  }
  return SyncJob(
    clientOpId: opId,
    entity: entity,
    op: _op(j['op']),
    payload: _mapa(j['payload'], 'payload'),
    syncVersion: j['sync_version'] as int?,
    // El servidor no usa createdAt —el orden ya viene dado por la posición en
    // el lote (§5.5)— pero el tipo lo pide.
    createdAt: DateTime.tryParse('${j['created_at']}')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

Map<String, Object?> pushResponseToJson(PushResult result) => {
      'server_time': result.serverTime.toUtc().toIso8601String(),
      'results': [
        for (final r in result.results)
          {
            'client_op_id': r.clientOpId,
            'outcome': r.outcome.name,
            if (r.syncVersion != null) 'sync_version': r.syncVersion,
            if (r.serverRow != null) 'server_row': r.serverRow,
            if (r.code.isNotEmpty) 'code': r.code,
            if (r.message.isNotEmpty) 'message': r.message,
            if (r.constraint.isNotEmpty) 'constraint': r.constraint,
            if (r.dependsOn != null) 'depends_on': r.dependsOn,
          },
      ],
    };

PushResult pushResponseFromJson(Map<String, Object?> json) => PushResult(
      serverTime: _fecha(json['server_time']),
      results: [
        for (final crudo in (json['results'] as List? ?? const []))
          _resultFromJson(_mapa(crudo, 'result')),
      ],
    );

JobResult _resultFromJson(Map<String, Object?> j) => JobResult(
      clientOpId: '${j['client_op_id']}',
      outcome: _outcome(j['outcome']),
      syncVersion: j['sync_version'] as int?,
      serverRow: (j['server_row'] as Map?)?.cast<String, Object?>(),
      code: (j['code'] as String?) ?? '',
      message: (j['message'] as String?) ?? '',
      constraint: (j['constraint'] as String?) ?? '',
      dependsOn: j['depends_on'] as String?,
    );

// --- pull -------------------------------------------------------------------

/// El pedido del pull como cuerpo (`public.sync_pull`, contrato §6.1).
///
/// `entities` es un array y no una lista con comas, y el sobre va en `device`,
/// como en el push. [watermark] y [limit] se omiten cuando son nulos: sin
/// watermark es una réplica desde cero, y sin limit decide el servidor.
Map<String, Object?> pullRequestToJson(
  ClientEnvelope sobre, {
  required List<String> entities,
  String? watermark,
  int? limit,
}) =>
    {
      'device': envelopeToJson(sobre),
      'entities': entities,
      if (watermark != null) 'watermark': watermark,
      if (limit != null) 'limit': limit,
    };

Map<String, Object?> pullResponseToJson(PullDelta delta) => {
      'server_time': delta.serverTime.toUtc().toIso8601String(),
      'watermark': delta.watermark,
      'has_more': delta.hasMore,
      'rows': delta.rows,
    };

PullDelta pullResponseFromJson(
  Map<String, Object?> json, {
  String? watermarkPrevio,
}) {
  final filas = <String, List<Map<String, Object?>>>{};
  for (final MapEntry(key: entidad, value: lista)
      in (json['rows'] as Map? ?? const {}).entries) {
    filas['$entidad'] = [
      for (final f in lista as List) (f as Map).cast<String, Object?>(),
    ];
  }

  return PullDelta(
    serverTime: _fecha(json['server_time']),
    // Si el servidor no manda uno nuevo, se conserva el que había: inventar uno
    // acá sería adelantar el cursor sin datos.
    watermark: _watermark(json['watermark']) ?? watermarkPrevio ?? '',
    hasMore: json['has_more'] == true,
    rows: filas,
  );
}

/// El watermark es un string opaco. Un objeto (el `jsonb` de `sync.pull()` sin
/// serializar) no se puede guardar ni devolver tal cual: es un servidor que no
/// cumple, y se dice con [FormatException] en vez de un `TypeError` que el
/// transporte no sabría clasificar.
String? _watermark(Object? valor) => switch (valor) {
      null => null,
      final String w => w,
      _ => throw FormatException('watermark tiene que ser un string: $valor'),
    };

// --- errores ----------------------------------------------------------------

Map<String, Object?> errorToJson(String code, String message) => {
      'code': code,
      'message': message,
    };

// --- comunes ----------------------------------------------------------------

Map<String, Object?> _mapa(Object? valor, String queEs) {
  if (valor is Map) return valor.cast<String, Object?>();
  throw FormatException('$queEs tiene que ser un objeto');
}

Op _op(Object? valor) => switch (valor) {
      'insert' => Op.insert,
      'update' => Op.update,
      'delete' => Op.delete,
      _ => throw FormatException('op inválida: $valor'),
    };

/// Un `outcome` que este cliente no conoce es un contrato desalineado. Tratarlo
/// como aceptado borraría de la cola un job que nunca subió.
JobOutcome _outcome(Object? valor) => switch (valor) {
      'accepted' => JobOutcome.accepted,
      'duplicate' => JobOutcome.duplicate,
      'conflict' => JobOutcome.conflict,
      _ => JobOutcome.invalid,
    };

DateTime _fecha(Object? valor) =>
    DateTime.tryParse('$valor')?.toUtc() ?? DateTime.now().toUtc();
