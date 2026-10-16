import 'model.dart';

/// Un job en `sync_queue`, con su estado (§5.1).
class QueuedJob {
  const QueuedJob({
    required this.id,
    required this.job,
    required this.state,
    this.code = '',
    this.message = '',
    this.doneAt,
    this.claimedAt,
    this.dependsOn,
  });

  /// Id local. Es lo que la app le pasa a `engine.requeue(jobId)`.
  final String id;

  final SyncJob job;
  final JobState state;

  /// Por qué quedó `INVALID`. Es lo que la UI le muestra al colportor.
  final String code;
  final String message;

  /// Cuándo pasó a `DONE`, para la purga a los 7 días (§5.8).
  final DateTime? doneAt;

  /// Cuándo un ciclo se lo llevó a `IN_FLIGHT`, o null si no está en vuelo.
  ///
  /// Es lo que hace posible distinguir "lo está mandando alguien ahora" de
  /// "quedó colgado": ver [JobStorePort.reclaimInFlight].
  final DateTime? claimedAt;

  /// En [JobState.waiting]: el id (la PK) de la fila que el servidor no tiene
  /// y que este job nombra. `null` en cualquier otro estado.
  final String? dependsOn;

  QueuedJob copyWith({
    JobState? state,
    String? code,
    String? message,
    DateTime? doneAt,
    DateTime? claimedAt,
    bool limpiarClaimedAt = false,
    SyncJob? job,
    String? dependsOn,
    bool limpiarDependsOn = false,
  }) =>
      QueuedJob(
        id: id,
        job: job ?? this.job,
        state: state ?? this.state,
        code: code ?? this.code,
        message: message ?? this.message,
        doneAt: doneAt ?? this.doneAt,
        claimedAt: limpiarClaimedAt ? null : (claimedAt ?? this.claimedAt),
        dependsOn: limpiarDependsOn ? null : (dependsOn ?? this.dependsOn),
      );
}

/// Lo que la app observa de la cola (§3, `engine.status`).
class SyncStatus {
  const SyncStatus({
    this.pending = 0,
    this.inFlight = 0,
    this.invalid = 0,
    this.blocked = 0,
    this.waiting = 0,
    this.lastSuccessAt,
    this.unauthorizedSince,
  });

  /// Esperando subir. Se reintentan indefinidamente al próximo trigger.
  final int pending;

  final int inFlight;

  /// En la cola de error, visibles. **Nunca se reintentan solos**: solo
  /// `engine.requeue(jobId)` los devuelve a `pending` (§5.1).
  final int invalid;

  /// Esperando que la colportora resuelva un conflicto (§2.2, vista 10). No
  /// suben hasta que la app reescriba la fila. Ver [JobState.blocked].
  final int blocked;

  /// Retenidos porque nombran una fila [blocked]. Ver [JobState.waiting].
  final int waiting;

  final DateTime? lastSuccessAt;

  /// Desde cuándo el servidor viene contestando `401`, o null si la sesión
  /// funciona.
  ///
  /// El `401` es transitorio (§5.1, B1): los jobs quedan en `pending` y no se
  /// pierde una sola venta. Pero si el refresh del token está roto, eso solo
  /// significa que el colportor reintenta para siempre **sin que nada se lo
  /// diga**: la pantalla muestra "sincronizando" toda la jornada y la cola no
  /// baja nunca. Ese es el riesgo que B1 anotó al decidir `transient`, y esto
  /// es lo que lo cubre: la app puede decir "volvé a iniciar sesión" en vez de
  /// dejarlo esperando.
  ///
  /// Solo lo limpia un ciclo que funcionó. Estar sin red no lo limpia: no
  /// saber si la sesión anda no es lo mismo que saber que anda.
  final DateTime? unauthorizedSince;

  @override
  String toString() => 'SyncStatus(pending: $pending, inFlight: $inFlight, '
      'invalid: $invalid, blocked: $blocked, waiting: $waiting, '
      'lastSuccessAt: $lastSuccessAt'
      '${unauthorizedSince == null ? '' : ', sin sesión desde '
          '$unauthorizedSince'})';
}
