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
    this.lastPushAt,
    this.lastPullAt,
    this.lastBackupAt,
    this.pullPausedReason,
    this.dataSaver = false,
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

  /// Cuándo terminó el último ciclo completo (subió lo pendiente **y** bajó el
  /// delta). Un ciclo con el pull en pausa por el ahorro de datos no cuenta.
  final DateTime? lastSuccessAt;

  /// La última vez que el servidor confirmó una escritura del colportor
  /// (HU-SYNC-007: «última fecha de push exitoso»). Sobrevive a reiniciar la
  /// app mientras ese job siga en la cola (los `DONE` se compactan a los 7 días).
  final DateTime? lastPushAt;

  /// La última vez que se bajó el delta con éxito (HU-SYNC-007). Vive en
  /// memoria: hasta el primer pull después de abrir la app es `null`.
  final DateTime? lastPullAt;

  /// El último backup que terminó bien desde que se abrió la app (HU-SYNC-007).
  /// `null` hasta que corra uno.
  final DateTime? lastBackupAt;

  /// Por qué el último ciclo no bajó el delta, o `null` si lo bajó. Hoy es
  /// [kDataSaverOnMobile]: el ahorro de datos está activo y no hay Wi-Fi
  /// (HU-SYNC-008). Lo limpia el próximo pull que corre.
  final String? pullPausedReason;

  /// El ahorro de datos está activo (HU-SYNC-008).
  final bool dataSaver;

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
      'lastSuccessAt: $lastSuccessAt, lastPushAt: $lastPushAt, '
      'lastPullAt: $lastPullAt'
      '${pullPausedReason == null ? '' : ', pull en pausa: $pullPausedReason'}'
      '${unauthorizedSince == null ? '' : ', sin sesión desde '
          '$unauthorizedSince'})';
}

/// El motivo con el que un ciclo deja el pull esperando por el ahorro de datos
/// (HU-SYNC-008): el modo está activo y el teléfono solo tiene datos móviles.
const kDataSaverOnMobile = 'data_saver_on_mobile';

/// Una operación que el servidor rechazó, lista para mostrar en «Ver detalle»
/// (HU-SYNC-007): qué tabla, cuándo, de qué tipo y por qué.
///
/// A propósito **no lleva el payload**: la fila puede tener datos personales
/// (una dirección, una nota) y la pantalla solo necesita saber de qué se trata.
/// Quien necesite la fila entera usa `SyncEngine.errorQueue`.
class FailedOperation {
  const FailedOperation({
    required this.jobId,
    required this.entity,
    required this.op,
    required this.createdAt,
    required this.code,
    required this.lastError,
  });

  /// El id que acepta `SyncEngine.requeue`.
  final String jobId;

  /// La tabla (nombre remoto).
  final String entity;

  final Op op;
  final DateTime createdAt;

  /// El código con el que el servidor la rechazó.
  final String code;

  /// El mensaje del servidor, sin datos personales (ver [sanitizarError]).
  final String lastError;
}

/// Saca de un mensaje de error lo que podría ser un dato del colportor o de un
/// cliente: el servidor devuelve cosas como `Key (email)=(a@b.com) already
/// exists` o `invalid input syntax for type date: "Juan Pérez"`.
///
/// Es de mejor esfuerzo y a propósito agresivo: se pierde precisión del
/// mensaje, no se filtra un valor. El `code` sigue siendo exacto. Lo que queda
/// no pasa de [largoMaximo] caracteres.
String sanitizarError(String mensaje, {int largoMaximo = 200}) {
  var s = mensaje
      // `Key (campo)=(valor)`: el valor va entre paréntesis.
      .replaceAll(RegExp(r'\([^)]*\)'), '(…)')
      // `...type date: "valor"` o `value: 'x'`.
      .replaceAll(RegExp(r':\s*("[^"]*"|' "'[^']*'" r')'), ': «…»')
      // Un correo suelto.
      .replaceAll(RegExp(r'\S+@\S+'), '…')
      // Teléfonos, documentos, ids largos de dígitos.
      .replaceAll(RegExp(r'\d{6,}'), '…');
  if (s.length > largoMaximo) s = '${s.substring(0, largoMaximo)}…';
  return s;
}
