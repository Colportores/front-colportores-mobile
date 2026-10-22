import 'dart:convert';

import '../core/model.dart';
import '../core/ports.dart';

/// El backend en memoria (§6).
///
/// Existe desde el Sprint 2 para que la app se desarrolle contra él sin esperar
/// al motor real (§1, §11), y para que la suite de conformidad (§8) corra en el
/// CI sin emulador ni red.
///
/// Por defecto se porta como un backend correcto: acepta, deduplica por
/// `client_op_id`, trata el insert sobre una PK existente como éxito idempotente
/// (§7), aplica LWW por `sync_version` y sirve el delta por watermark. Lo que el
/// test quiera que salga mal, lo pide antes con [failWith] u [offline].
///
/// ```dart
/// final transport = FakeSyncTransport()
///   ..seed('venta', [ventaDelServidor]);   // lo que ya subió otro dispositivo
/// transport.failWith(422);                 // la próxima llamada rebota
/// ```
class FakeSyncTransport implements SyncTransport {
  FakeSyncTransport({
    this.pkField = 'id',
    this.versionField = 'sync_version',
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  /// Nombre de la PK dentro del payload — el UUID v7 del dispositivo (§7).
  /// **Pendiente de fijar en v1.0**: hoy el contrato no nombra este campo.
  final String pkField;

  /// Campo de versión que declara cada `SyncTableAdapter` (§3).
  final String versionField;

  final DateTime Function() _clock;

  // --- lo que el test observa -------------------------------------------------

  /// Todo lote que llegó, en orden, **incluidos los que fallaron**: para saber
  /// si el motor reintentó hay que poder ver el intento que rebotó.
  final List<PushBatch> batches = [];

  /// Cada pull pedido. Un watermark repetido significa que el motor no avanzó,
  /// que es lo que hay que verificar cuando aplicar la transacción local falla.
  final List<({List<String> entities, String? watermark, int? limit})> pulls =
      [];

  /// `client_op_id` que el backend ya vio. Es la medición de §5.3: reintentar
  /// no puede hacer crecer este conjunto.
  final Set<String> appliedOpIds = {};

  int get jobsReceived => batches.fold(0, (n, b) => n + b.length);

  /// Las filas que hay "en el servidor" para una entidad, sin las borradas.
  List<Map<String, Object?>> rowsOf(String entity) => [
        for (final fila in (_tables[entity] ?? {}).values)
          if (!fila.deleted) fila.payload,
      ];

  // --- lo que el test programa ------------------------------------------------

  /// La próxima llamada —push o pull, la que venga— falla con este status,
  /// clasificado por [kindForStatus]. Se consume una sola vez.
  void failWith(int status, {String code = 'FAKE', Duration? retryAfter}) {
    _failures.add(TransportFailure.fromStatus(status,
        code: code, message: 'falla simulada', retryAfter: retryAfter));
  }

  /// Las próximas [times] llamadas fallan sin respuesta, como un timeout.
  void failTransient([int times = 1]) {
    for (var i = 0; i < times; i++) {
      _failures.add(const TransportFailure(FailureKind.transient,
          message: 'sin conexión'));
    }
  }

  /// Descarta las fallas programadas que todavía no se consumieron.
  ///
  /// Es cómo se termina una tormenta en un test: `online()` devuelve la red,
  /// pero las fallas encoladas siguen ahí esperando su turno.
  void clearFailures() => _failures.clear();

  /// Sin red hasta [online]. A diferencia de [failTransient], no se consume:
  /// sirve para los siete días en modo avión.
  void offline() => _offline = true;
  void online() => _offline = false;

  /// El lote llega y **se aplica**, y recién después se corta la conexión.
  ///
  /// Es el escenario que justifica el `client_op_id` (§5.3): el job ya está en
  /// el servidor y el motor no lo sabe, así que reintenta. El reintento tiene
  /// que volver [JobOutcome.duplicate], no crear una segunda venta.
  void loseNextResponse([int times = 1]) => _loseResponse += times;

  /// Este job siempre vuelve [JobOutcome.invalid], con el resto del lote
  /// aceptado (§5.1).
  void rejectJob(String clientOpId, String code, [String message = '']) {
    _rejected[clientOpId] = (code: code, message: message);
  }

  /// Deja de rechazar: el dato se corrigió del lado del backend.
  void clearRejections() => _rejected.clear();

  /// Filas que ya están en el servidor antes de que el motor hable.
  ///
  /// Es lo que necesita el escenario de recuperación de §8: las ventas que
  /// subieron después del último backup y tienen que aparecer en la fase 3.
  void seed(String entity, List<Map<String, Object?>> rows) {
    for (final fila in rows) {
      _apply(entity, fila, version: (fila[versionField] as int?) ?? 1);
    }
  }

  // --- SyncTransport ----------------------------------------------------------

  @override
  Future<PushResult> push(PushBatch batch) async {
    batches.add(batch);
    _maybeFail();

    final results = <JobResult>[];
    for (final job in batch.jobs) {
      results.add(_applyJob(job));
    }

    if (_loseResponse > 0) {
      _loseResponse--;
      throw const TransportFailure(FailureKind.transient,
          message: 'el lote se aplicó, pero la respuesta no volvió');
    }

    return PushResult(serverTime: _clock(), results: results);
  }

  @override
  Future<PullDelta> pull({
    required List<String> entities,
    String? watermark,
    int? limit,
  }) async {
    pulls.add((entities: entities, watermark: watermark, limit: limit));
    _maybeFail();

    final desde = _seqOf(watermark);
    final pendientes = <({String entity, _Row row})>[];
    for (final entity in entities) {
      for (final row in (_tables[entity] ?? <String, _Row>{}).values) {
        if (row.seq > desde) pendientes.add((entity: entity, row: row));
      }
    }
    pendientes.sort((a, b) => a.row.seq.compareTo(b.row.seq));

    final tope = limit ?? pendientes.length;
    final servidas = pendientes.take(tope).toList();
    final rows = <String, List<Map<String, Object?>>>{};
    for (final p in servidas) {
      (rows[p.entity] ??= []).add(p.row.payload);
    }

    return PullDelta(
      serverTime: _clock(),
      // Sin novedades el watermark vuelve igual que como llegó: pedir dos veces
      // desde el mismo punto devuelve dos veces lo mismo.
      watermark:
          servidas.isEmpty ? (watermark ?? '') : 'w-${servidas.last.row.seq}',
      hasMore: servidas.length < pendientes.length,
      rows: rows,
    );
  }

  // --- el "servidor" ----------------------------------------------------------

  final List<TransportFailure> _failures = [];
  final Map<String, ({String code, String message})> _rejected = {};
  final Map<String, Map<String, _Row>> _tables = {};
  bool _offline = false;
  int _loseResponse = 0;
  int _seq = 0;

  JobResult _applyJob(SyncJob job) {
    // El cache de client_op_id (TTL 24 h, §4) gana sobre cualquier validación:
    // un op que el backend ya aplicó vuelve `duplicate` y no se re-valida.
    //
    // El orden importa. Al revés, un job aplicado cuya respuesta se perdió y
    // que en el reintento cae en una validación quedaría INVALID **con la fila
    // ya escrita en el servidor**: un estado que ningún backend con cache de
    // idempotencia puede producir, y que dejaría al colportor con una venta
    // en la cola de error que en realidad ya cobró.
    if (appliedOpIds.contains(job.clientOpId)) {
      return JobResult(
          clientOpId: job.clientOpId, outcome: JobOutcome.duplicate);
    }

    final rechazo = _rejected[job.clientOpId];
    if (rechazo != null) {
      return JobResult(
        clientOpId: job.clientOpId,
        outcome: JobOutcome.invalid,
        code: rechazo.code,
        message: rechazo.message,
      );
    }

    appliedOpIds.add(job.clientOpId);

    final pk = job.payload[pkField];
    if (pk == null) {
      return JobResult(
        clientOpId: job.clientOpId,
        outcome: JobOutcome.invalid,
        code: 'PK_FALTANTE',
        message: 'el payload no trae "$pkField"',
      );
    }

    final tabla = _tables[job.entity] ??= {};
    final actual = tabla['$pk'];

    switch (job.op) {
      case Op.insert:
        // §7: insert sobre una PK que ya existe = éxito idempotente. El UUID v7
        // lo generó el dispositivo, así que la fila es la misma, no otra.
        if (actual != null) {
          return JobResult(
            clientOpId: job.clientOpId,
            outcome: JobOutcome.duplicate,
            syncVersion: actual.version,
          );
        }
        final fila = _apply(job.entity, job.payload, version: 1);
        return JobResult(
          clientOpId: job.clientOpId,
          outcome: JobOutcome.accepted,
          syncVersion: fila.version,
        );

      case Op.update:
      case Op.delete:
        if (actual == null) {
          return JobResult(
            clientOpId: job.clientOpId,
            outcome: JobOutcome.invalid,
            code: 'FILA_INEXISTENTE',
            message: '$pk no existe en ${job.entity}',
          );
        }
        // §5.4: si el servidor tiene una versión más nueva, 409 → LWW.
        if (job.syncVersion != null && job.syncVersion != actual.version) {
          return JobResult(
            clientOpId: job.clientOpId,
            outcome: JobOutcome.conflict,
            syncVersion: actual.version,
            serverRow: actual.payload,
          );
        }
        final fila = _apply(job.entity, job.payload,
            version: actual.version + 1, deleted: job.op == Op.delete);
        return JobResult(
          clientOpId: job.clientOpId,
          outcome: JobOutcome.accepted,
          syncVersion: fila.version,
        );
    }
  }

  _Row _apply(String entity, Map<String, Object?> payload,
      {required int version, bool deleted = false}) {
    final pk = '${payload[pkField]}';
    final fila = _Row(
      payload: {...payload, versionField: version},
      version: version,
      seq: ++_seq,
      deleted: deleted,
    );
    (_tables[entity] ??= {})[pk] = fila;
    return fila;
  }

  void _maybeFail() {
    if (_offline) {
      throw const TransportFailure(FailureKind.transient, message: 'offline');
    }
    if (_failures.isEmpty) return;
    throw _failures.removeAt(0);
  }

  /// El watermark es opaco para el motor, así que acá adentro es la posición.
  int _seqOf(String? watermark) {
    if (watermark == null || watermark.isEmpty) return 0;
    return int.tryParse(watermark.split('-').last) ?? 0;
  }
}

class _Row {
  _Row({
    required this.payload,
    required this.version,
    required this.seq,
    required this.deleted,
  });

  final Map<String, Object?> payload;
  final int version;

  /// Orden de escritura en el servidor. Es lo que ordena el delta del pull.
  final int seq;

  final bool deleted;
}

/// Tamaño aproximado de un lote en bytes, para el tope de ~1 MB de §5.5.
int estimatedBytes(PushBatch batch) => utf8
    .encode(jsonEncode([
      for (final job in batch.jobs)
        {
          'client_op_id': job.clientOpId,
          'entity': job.entity,
          'op': job.op.name,
          'sync_version': job.syncVersion,
          'payload': job.payload,
        }
    ]))
    .length;
