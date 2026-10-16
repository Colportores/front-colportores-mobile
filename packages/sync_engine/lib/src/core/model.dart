// Los tipos que cruzan la frontera entre el motor y el transporte.
//
// Referencias al Contrato del motor de sincronización (sync_engine) v0.9.2 y a
// ADR-013. Nada de acá sabe qué es HTTP, Supabase ni el BFF: eso vive en
// lib/src/adapters/ (R-A1).

/// Qué le pasó a una fila en la DB local (§3, `engine.stage`).
enum Op { insert, update, delete }

/// Estados de un job en `sync_queue` (§5.1). **Sin retry counter**: un error
/// transitorio deja el job en [pending] y se reintenta indefinidamente al
/// próximo trigger; uno de payload lo deja en [invalid], visible, para siempre.
///
/// [blocked] y [waiting] son el «en espera» de §2.2: lo que el servidor no
/// guardó por un conflicto que tiene que resolver la colportora, y lo que
/// cuelga de eso. Ninguno de los dos se reintenta solo, y ninguno es un error:
/// vuelven a [pending] cuando la app escribe la fila de nuevo (ver
/// `SyncEngine.stage`).
enum JobState {
  pending,
  inFlight,
  invalid,
  done,

  /// El servidor no lo aplicó por un conflicto sin `server_row`: hoy, el alta o
  /// la corrección de una ubicación a menos de 100 m de otra con la misma
  /// dirección (`23505` `ubicacion_direccion_unica`, §2.2). La fila queda en el
  /// teléfono y la app la resuelve en la vista 10: cambiando la dirección o
  /// uniéndola con la otra. Las dos cosas son escribir la fila otra vez, y eso
  /// es lo que la devuelve a [pending].
  blocked,

  /// Nombra una fila que el servidor no tiene porque está [blocked] (o porque
  /// a su vez espera): `ESPERA_ALTA_EN_CONFLICTO`, o el motor que lo retuvo
  /// antes de mandarlo. [QueuedJob.dependsOn] dice cuál. Vuelve a [pending]
  /// junto con esa fila, o antes si la app lo reescribe sin nombrarla.
  waiting,
}

/// Una escritura local esperando subir.
///
/// La idempotencia se apoya en dos cosas distintas y ambas hacen falta (§5.3):
/// [clientOpId] identifica **el intento** y lo deduplica el cache del backend
/// (TTL 24 h); la PK dentro de [payload] es un UUID v7 generado en el
/// dispositivo, y es lo que hace que el replay de §7 siga siendo idempotente
/// cuando el backup es más viejo que ese TTL.
class SyncJob {
  const SyncJob({
    required this.clientOpId,
    required this.entity,
    required this.op,
    required this.payload,
    required this.createdAt,
    this.syncVersion,
    this.rowPk,
  });

  /// UUID del job. Reintentar N veces jamás duplica una venta o un cobro.
  final String clientOpId;

  /// Nombre remoto de la entidad, el que declara su `SyncTableAdapter`.
  final String entity;

  final Op op;

  /// Lo que devolvió `toSyncJson()`. Incluye la PK.
  final Map<String, Object?> payload;

  /// Versión esperada de la fila (§5.4). `null` en [Op.insert].
  /// Si el servidor tiene una más nueva: 409 → LWW.
  final int? syncVersion;

  /// Los jobs de una misma entidad se suben en orden de creación (§5.5).
  final DateTime createdAt;

  /// La PK de la fila que escribe: el valor de la columna `SyncSpec.pk` del
  /// payload. La pone `SyncEngine.stage`, y la cola la indexa para encontrar
  /// las escrituras de una fila sin recorrerla entera (`unsentFor`). `null` en
  /// un job armado a mano sin ella: ese no se compacta ni recibe la versión.
  final String? rowPk;

  SyncJob copyWith({
    Map<String, Object?>? payload,
    int? syncVersion,
    DateTime? createdAt,
  }) =>
      SyncJob(
        clientOpId: clientOpId,
        entity: entity,
        op: op,
        payload: payload ?? this.payload,
        syncVersion: syncVersion ?? this.syncVersion,
        createdAt: createdAt ?? this.createdAt,
        rowPk: rowPk,
      );
}

/// Un lote de jobs para un `POST /sync/push` contra el BFF (§6).
///
/// El tope es de tamaño, no de cantidad: ≤ 1 MB típico (§5.5, RR-02).
class PushBatch {
  const PushBatch(this.jobs);

  final List<SyncJob> jobs;

  int get length => jobs.length;
  bool get isEmpty => jobs.isEmpty;
}

/// La versión del formato de cable que habla este motor (§5.3 del contrato de
/// datos).
///
/// Sube **solo ante un cambio incompatible**, nunca ante uno aditivo (§9). El
/// BFF la compara contra la mínima que soporta y responde `426` a lo que ya no
/// entiende: es la regla 3 del §3 de arquitectura, y sin ella un colportor que
/// no actualiza manda payloads de otro esquema y el servidor los toma como
/// buenos.
const int kWireSchemaVersion = 1;

/// Quién está hablando: el sobre de §5.3, que viaja en **las dos direcciones**
/// de cada ciclo.
///
/// No es parte del dato que se sincroniza sino del mensaje que lo lleva, y por
/// eso no cuelga de [PushBatch]: es del cliente, y es el mismo para todos los
/// lotes de una misma instalación.
///
/// Sin esto no existe "el dispositivo": dos teléfonos del mismo colportor son
/// indistinguibles para el servidor, la telemetría de `sync.log` no puede
/// separarlos y no hay forma de cerrar la sesión de uno perdido sin cerrar
/// todas.
class ClientEnvelope {
  const ClientEnvelope({
    required this.deviceId,
    required this.appVersion,
    this.schemaVersion = kWireSchemaVersion,
  });

  /// UUID de la **instalación**, no del colportor ni del hardware.
  ///
  /// Lo genera el dispositivo en el primer arranque y lo guarda en
  /// `flutter_secure_storage`: así existe antes del login —que es lo que
  /// permite encolar sin sesión y subir después— y una reinstalación estrena
  /// uno, que es lo correcto, porque la réplica también arranca de cero.
  final String deviceId;

  /// La versión de la app, para leer la telemetría. No decide nada: lo que
  /// corta un push viejo es [schemaVersion].
  final String appVersion;

  /// La del formato de cable, no la de la app. Ver [kWireSchemaVersion].
  final int schemaVersion;

  @override
  String toString() =>
      'ClientEnvelope($deviceId, app $appVersion, cable v$schemaVersion)';
}

/// Qué hizo el servidor con un job (§5.1, §5.3, §7).
enum JobOutcome {
  /// Se aplicó. → `DONE`.
  accepted,

  /// Ya estaba: mismo `client_op_id`, o un insert sobre una PK que ya existe.
  /// **Es un éxito idempotente, no un error** (§7): también → `DONE`.
  duplicate,

  /// Con [JobResult.serverRow]: el servidor tiene una `sync_version` más
  /// nueva. El motor resuelve por LWW (§5.4) y el job no queda `INVALID`.
  ///
  /// Sin [JobResult.serverRow]: no se aplicó y no hay fila con la que
  /// resolver (§2.2). Con `code` `ESPERA_ALTA_EN_CONFLICTO` el job pasa a
  /// [JobState.waiting]; con cualquier otro (el `23505` de dirección única), a
  /// [JobState.blocked].
  conflict,

  /// Error de payload (400/422/403). → `INVALID`, visible, sin reintento
  /// automático. Solo `engine.requeue(jobId)` lo vuelve a poner en `PENDING`.
  invalid,
}

/// El `code` del [JobOutcome.conflict] de lo que cuelga de un alta en
/// conflicto del mismo lote (§2.2, §6.1). Trae [JobResult.dependsOn].
const String kCodigoEsperaAltaEnConflicto = 'ESPERA_ALTA_EN_CONFLICTO';

/// El resultado de un job dentro del lote.
class JobResult {
  const JobResult({
    required this.clientOpId,
    required this.outcome,
    this.syncVersion,
    this.serverRow,
    this.code = '',
    this.message = '',
    this.constraint = '',
    this.dependsOn,
  });

  final String clientOpId;
  final JobOutcome outcome;

  /// Versión que quedó en el servidor tras aplicar.
  final int? syncVersion;

  /// Solo en [JobOutcome.conflict]: la fila que el servidor tiene ahora, que es
  /// lo que el motor necesita para resolver el LWW sin un pull extra.
  final Map<String, Object?>? serverRow;

  final String code;
  final String message;

  /// La restricción que saltó, cuando el servidor la nombra. Hoy solo viene en
  /// el [JobOutcome.conflict] de dirección única (`code` `23505`, constraint
  /// `ubicacion_direccion_unica`, §2.2), que llega **sin** [serverRow]: la fila
  /// queda en el teléfono y la app la resuelve en la vista 10.
  final String constraint;

  /// En el [JobOutcome.conflict] con `code` `ESPERA_ALTA_EN_CONFLICTO` (§6.1):
  /// el id de la fila en espera de la que cuelga este job. Sin [serverRow].
  final String? dependsOn;

  @override
  String toString() => '$clientOpId → ${outcome.name}'
      '${code.isEmpty ? '' : ' ($code)'}';
}

/// Respuesta de un push. Aceptación por job: un `INVALID` no tumba el lote.
class PushResult {
  const PushResult({required this.serverTime, required this.results});

  final DateTime serverTime;
  final List<JobResult> results;

  Iterable<JobResult> byOutcome(JobOutcome o) =>
      results.where((r) => r.outcome == o);

  /// Los que el motor puede marcar `DONE` (§5.1).
  Iterable<String> get settled => results
      .where((r) =>
          r.outcome == JobOutcome.accepted || r.outcome == JobOutcome.duplicate)
      .map((r) => r.clientOpId);
}

/// El delta que baja del servidor.
class PullDelta {
  const PullDelta({
    required this.serverTime,
    required this.watermark,
    required this.hasMore,
    required this.rows,
    this.outOfArea = const {},
    this.areaReset = const {},
  });

  final DateTime serverTime;

  /// Opaco para el motor: se guarda tal cual y se devuelve tal cual.
  ///
  /// Se persiste **después** de aplicar el delta en la transacción local. Si
  /// aplicar falla, el watermark no avanza y el próximo pull trae lo mismo. Es
  /// también lo que la fase 1 de §7 deja puesto al restaurar un backup.
  final String watermark;

  final bool hasMore;

  /// Entidad → filas. Una entidad ausente significa "sin cambios": el motor no
  /// borra nada por ausencia.
  final Map<String, List<Map<String, Object?>>> rows;

  /// Entidad → ids de las filas que salieron del área del colportor en este
  /// tramo (§2.1, `out_of_area` de backend 0016): otro las movió adonde él no
  /// trabaja. **No se borran**: la app las marca «fuera del área».
  final Map<String, List<String>> outOfArea;

  /// Las entidades que este pull arrancó de cero porque cambió el área (§2.1,
  /// `area_reset` de backend 0016): le asignaron o cambiaron la zona, o empezó
  /// o terminó una campaña. Lo que el teléfono tenía de ellas y no vuelva a
  /// bajar hasta el final de la descarga (`hasMore` en `false`) quedó fuera
  /// del área nueva. El motor lo deduce; el servidor no guarda el área vieja
  /// (decisión de Cristian, 02/10, backend-supabase#37).
  final Set<String> areaReset;
}

/// Lo que acompaña a las filas de una página del pull, para que el store lleve
/// la cuenta de qué quedó fuera del área (§2.1).
class PullNotices {
  const PullNotices({
    this.outOfArea = const {},
    this.areaReset = const {},
    this.complete = true,
  });

  /// Sin avisos y con la descarga terminada.
  static const none = PullNotices();

  /// Ver [PullDelta.outOfArea].
  final Map<String, List<String>> outOfArea;

  /// Ver [PullDelta.areaReset]. Llega en la primera página de la descarga que
  /// arranca de cero.
  final Set<String> areaReset;

  /// Es la última página (`hasMore` en `false`): lo que estaba a la espera de
  /// volver a bajar desde un [areaReset] y no bajó, quedó fuera del área.
  final bool complete;

  bool get isEmpty => outOfArea.isEmpty && areaReset.isEmpty;
}

/// La única clasificación que el motor hace de un error (§5.1).
///
/// Lleva una categoría y no un status HTTP a propósito: el núcleo no sabe que
/// existe HTTP. La traducción desde el status está en [kindForStatus] para que
/// el fake y los transportes reales no puedan discrepar; `SupabaseRpcTransport`
/// la mira después del `code` de PostgREST (`kindForRpcError`, §6.1).
enum FailureKind {
  /// Red, timeout, `5xx`, `429`. El job vuelve a `PENDING` y se reintenta al
  /// próximo trigger, indefinidamente y sin contador.
  transient,

  /// `400`, `403`, `422`. El job va a `INVALID`.
  payload,

  /// `409`. Hay una versión más nueva en el servidor: resolución LWW (§5.4).
  conflict,
}

extension FailureKindX on FailureKind {
  /// Si el mismo job, tal cual, se reintenta solo al próximo trigger.
  bool get retriable => this == FailureKind.transient;

  /// Estado en el que queda un job afectado por esta falla (§5.1).
  /// [FailureKind.conflict] no aparece: no deja al job en un estado, lo manda
  /// a resolución LWW.
  JobState get resultingState => switch (this) {
        FailureKind.transient => JobState.pending,
        FailureKind.payload => JobState.invalid,
        FailureKind.conflict => JobState.inFlight,
      };
}

/// Traduce un status HTTP a la clasificación de §5.1.
///
/// El `401` no está en la tabla del contrato. Queda como [FailureKind.transient]
/// porque el refresh del JWT es de la app (§10): el job espera y sube al
/// próximo trigger, ya con el token nuevo. **Cerrado (B1)**: la sesión es
/// nuestra, el dato es del colportor, y mandarlo a `INVALID` porque venció un
/// token lo esconde detrás de un "reintentar" que no tiene por qué entender.
///
/// El riesgo que B1 anotó —un refresh roto reintentando para siempre en
/// silencio— lo cubre `SyncStatus.unauthorizedSince`, no un cambio de esta
/// clasificación.
FailureKind kindForStatus(int status) => switch (status) {
      400 || 403 || 422 => FailureKind.payload,
      409 => FailureKind.conflict,
      _ => FailureKind.transient,
    };

/// Falla de una llamada completa al transporte.
///
/// Los errores de un job puntual no llegan por acá: vuelven como
/// [JobResult] dentro de [PushResult], porque el resto del lote sí entró.
class TransportFailure implements Exception {
  const TransportFailure(
    this.kind, {
    this.status,
    this.code = '',
    this.message = '',
    this.retryAfter,
  });

  /// Sin status: la llamada no llegó a tener respuesta (offline, timeout).
  TransportFailure.fromStatus(int this.status,
      {this.code = '', this.message = '', this.retryAfter})
      : kind = kindForStatus(status);

  final FailureKind kind;
  final int? status;
  final String code;
  final String message;

  /// Del `Retry-After` de un `429`.
  final Duration? retryAfter;

  @override
  String toString() => 'TransportFailure(${kind.name}'
      '${status == null ? '' : ' $status'})'
      '${code.isEmpty ? '' : ' $code'}${message.isEmpty ? '' : ' — $message'}';
}
