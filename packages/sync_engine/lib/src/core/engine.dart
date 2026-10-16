import 'dart:async';

import 'backup.dart';
import 'backup_service.dart';
import 'batch.dart';
import 'model.dart';
import 'ports.dart';
import 'queue.dart';
import 'adapter.dart';
import 'recover.dart';
import 'spec.dart';
import 'uuid.dart';

/// Por qué arrancó un ciclo (§5.2). **No hay timer periódico**: un motor que
/// sincroniza cada N minutos gasta batería para descubrir que no pasó nada.
enum SyncTrigger {
  /// Volvió la red.
  connectivity,

  /// La app pasó a primer plano.
  appResumed,

  /// Se stageó una entidad `critical`: una venta, un cobro, una jornada.
  criticalWrite,

  /// El colportor apretó "Sincronizar ahora" (§3, `syncNow`).
  manual,

  /// Llegó un evento de Supabase Realtime (§5.6). A diferencia de los demás,
  /// este ciclo **solo baja**: un cambio remoto no es motivo para subir la cola.
  realtime,
}

/// Cómo terminó un ciclo.
class SyncOutcome {
  const SyncOutcome({
    required this.trigger,
    this.pushed = 0,
    this.invalidated = 0,
    this.conflicts = 0,
    this.pulled = 0,
    this.skipped = false,
    this.failure,
  });

  final SyncTrigger trigger;
  final int pushed;
  final int invalidated;
  final int conflicts;
  final int pulled;

  /// El ciclo no llegó a correr: ahorro de datos, o ya había uno en curso.
  final bool skipped;

  /// La falla transitoria que lo cortó. Los jobs volvieron a `PENDING`.
  final TransportFailure? failure;

  bool get ok => !skipped && failure == null;
}

/// El motor: cola, lotes, reintentos, conflictos, realtime, backup y
/// recuperación de dispositivo (§5, §7).
class SyncEngine {
  SyncEngine({
    required SpecRegistry specs,
    required SyncTransport transport,
    required JobStorePort jobs,
    required LocalStorePort store,
    List<SyncTableAdapter<Object?>> adapters = const [],
    ConnectivityPort? connectivity,
    RealtimePort? realtime,
    BackupService? backup,
    DateTime Function()? clock,
    UuidV7? uuid,
    this.batchLimit = 500,
    this.realtimeDebounce = const Duration(milliseconds: 300),
    this.criticalDebounce = const Duration(seconds: 2),
    this.inFlightLease = const Duration(minutes: 10),
  })  : _specs = specs,
        _uuid = uuid ?? UuidV7(),
        _adapters = {for (final a in adapters) a.remoteName: a},
        _backup = backup,
        _realtimePort = realtime,
        _transport = transport,
        _jobs = jobs,
        _store = store,
        _clock = clock ?? (() => DateTime.now().toUtc()) {
    if (connectivity != null) {
      _conn = connectivity.onlineChanges.listen((online) {
        if (online) trigger(SyncTrigger.connectivity);
      });
    }
    resubscribe();
  }

  final SpecRegistry _specs;
  final SyncTransport _transport;
  final JobStorePort _jobs;
  final LocalStorePort _store;
  final RealtimePort? _realtimePort;
  final UuidV7 _uuid;
  final Map<String, SyncTableAdapter<Object?>> _adapters;
  final BackupService? _backup;
  final DateTime Function() _clock;

  /// Backup E2E (§3, ADR-003). Lanza si el motor se armó sin los puertos de
  /// backup: es un error de cableado, no algo que la app deba atrapar.
  BackupService get backup =>
      _backup ??
      (throw StateError('este SyncEngine se armó sin BackupService: '
          'faltan ArchivePort, CryptoPort y SnapshotPort'));

  /// Ventana de coalescencia de eventos realtime.
  ///
  /// Actualizar una lista de precios dispara un evento por fila. Sin esta
  /// ventana serían N pulls para un solo cambio del administrador. No es un
  /// timer periódico —no despierta si no pasa nada—, es la espera a que el
  /// burst termine.
  final Duration realtimeDebounce;

  /// Ventana de coalescencia de las escrituras críticas.
  ///
  /// Una venta con tres items son cuatro `stage()` seguidos, y sin esta ventana
  /// son cuatro requests HTTP para una sola operación del colportor. Dos
  /// segundos no cambian nada de la garantía —lo crítico es no esperar al
  /// próximo trigger, no salir en el mismo milisegundo— y en una jornada bajan
  /// los pushes de 21 a 2.
  ///
  /// [flush] la salta cuando hace falta ya: al mandar la app a segundo plano,
  /// por ejemplo.
  final Duration criticalDebounce;

  /// Cuántos jobs se toman de la cola por ciclo. El tope real del lote es de
  /// bytes ([kMaxBatchBytes]); este es el techo de cuánto se mira por vez.
  final int batchLimit;

  /// Cuánto puede estar un job en `IN_FLIGHT` antes de darlo por colgado.
  ///
  /// Diez minutos es mucho más que cualquier push real —el timeout del
  /// transporte son 30 s— y ese margen es a propósito: el trabajo en segundo
  /// plano (RF-SY07) corre en otro isolate con su propio motor, y un lease
  /// corto haría que se lleve puestos jobs que el primer plano está mandando en
  /// ese momento. Se reenviarían en paralelo: no se duplica ninguna venta —el
  /// `client_op_id` lo corta— pero el colportor paga el viaje dos veces.
  ///
  /// El precio de que sea largo lo paga un caso raro: si el proceso muere justo
  /// mientras empujaba, esos jobs esperan hasta diez minutos. No se pierden, y
  /// como el reclamo corre en cada ciclo, no hace falta reiniciar la app.
  final Duration inFlightLease;

  StreamSubscription<bool>? _conn;
  StreamSubscription<String>? _realtimeSub;
  Timer? _realtimeTimer;
  Timer? _criticalTimer;

  /// La zona donde se construyó el motor, para programar sus timers.
  ///
  /// En Dart el callback de un `Timer` corre en la zona donde el timer se
  /// **creó**, y `stage()` se llama adentro de la transacción de la app: eso es
  /// el contrato (§3), la fila de negocio y su job entran juntas o no entra
  /// ninguna. Pero adentro de `db.transaction()` la zona es la del ORM, que
  /// enruta cada consulta al ejecutor de esa transacción — y para cuando el
  /// debounce dispara, la transacción ya cerró.
  ///
  /// El síntoma es el peor de todos: la venta queda guardada y encolada, la
  /// pantalla la muestra, y el ciclo automático revienta contra una transacción
  /// muerta. Nadie ve nada, porque el ciclo se dispara con `unawaited`. La venta
  /// espera al próximo trigger, que puede ser el botón manual… o nada.
  ///
  /// Se captura la zona de construcción y no `Zone.root` para no romper a quien
  /// corra el motor bajo `FakeAsync`: ahí el motor se construye adentro de la
  /// zona falsa, y sus timers tienen que seguir siendo los de esa zona.
  final Zone _zona = Zone.current;
  bool _realtimePending = false;

  /// Un trigger automático que llegó mientras había algo corriendo.
  ///
  /// Saltearlo y olvidarlo deja lo pendiente esperando al **próximo** trigger,
  /// que puede tardar horas: si vuelve la red durante una recuperación, esa es
  /// justo la señal que no hay que tirar.
  SyncTrigger? _pendiente;
  bool _disposed = false;
  final _status = StreamController<SyncStatus>.broadcast();
  Future<SyncOutcome>? _running;
  bool _dataSaver = false;
  DateTime? _lastSuccessAt;

  /// Desde cuándo el backend contesta `401`. Ver [SyncStatus.unauthorizedSince].
  DateTime? _sinSesionDesde;

  /// Estado de la cola para la UI (§3). No emite hasta que algo cambia.
  Stream<SyncStatus> get status => _status.stream;

  /// El ciclo en curso, si hay uno. Los tests lo esperan en vez de dormir.
  Future<SyncOutcome> get settled =>
      _running ??
      Future.value(
          const SyncOutcome(trigger: SyncTrigger.manual, skipped: true));

  /// Encola una escritura local (§3).
  ///
  /// Se llama **dentro de la misma transacción** en la que la app escribe la
  /// fila de negocio: si el insert entra y el stage no, el dato existe en el
  /// celular y nunca sube.
  ///
  /// El `client_op_id` lo genera el motor (§5.3): es un detalle de idempotencia
  /// del transporte, no algo que la capa de datos tenga que inventar bien. Se
  /// puede pasar uno solo para tests o para reconstruir un job a mano.
  ///
  /// Lanza [LocalOnlyViolationError] si [entity] es `local`, y
  /// [UnregisteredEntityError] si no tiene `SyncSpec`.
  Future<String> stage(
    String entity,
    Op op,
    Map<String, Object?> payload, {
    String? clientOpId,
    int? syncVersion,
  }) async {
    // Encolar en un motor apagado es escribir en una cola que nadie va a
    // vaciar. Como `stage()` se llama dentro de la transacción de la app,
    // fallar acá hace que tampoco se escriba la fila de negocio: mejor no
    // guardar la venta que guardarla y no subirla nunca.
    _verificarVivo();
    _specs.assertStageable(entity);

    final id = await _jobs.append(SyncJob(
      clientOpId: clientOpId ?? _uuid.next(),
      entity: entity,
      op: op,
      payload: payload,
      syncVersion: syncVersion,
      createdAt: _clock(),
    ));
    await _emit();

    if (_specs.of(entity).critical) {
      _criticalTimer?.cancel();
      _criticalTimer = _zona.createTimer(criticalDebounce, () {
        unawaited(trigger(SyncTrigger.criticalWrite));
      });
    }
    return id;
  }

  /// (Re)suscribe a las entidades `realtime` (§5.6).
  ///
  /// La llama el constructor y la fase 4 de §7: en un dispositivo nuevo hay que
  /// volver a suscribirse después de repoblar los catálogos.
  void resubscribe() {
    final puerto = _realtimePort;
    if (puerto == null) return;
    final entidades = _specs.realtime;
    if (entidades.isEmpty) return;

    _realtimeSub?.cancel();
    _realtimeSub = puerto.subscribe(entidades).listen((_) {
      // Qué entidad cambió no altera lo que hay que hacer: bajar el delta.
      _realtimePending = true;
      _realtimeTimer?.cancel();
      _realtimeTimer =
          _zona.createTimer(realtimeDebounce, () => unawaited(_drainRealtime()));
    });
  }

  /// Como [stage], pero desde la fila tipada de la app.
  ///
  /// Es la forma que conviene usar: el `SyncTableAdapter` es la única fuente de
  /// la entidad, del payload y de la `sync_version`, así que no hay manera de
  /// mandar el payload de una entidad con el nombre de otra.
  Future<String> stageRow<T>(T row, Op op, {String? clientOpId}) {
    final adaptador = _adapterFor<T>(row);
    return stage(
      adaptador.remoteName,
      op,
      adaptador.toSyncJson(row),
      clientOpId: clientOpId,
      // En un insert no hay versión previa que esperar (§5.4).
      syncVersion: op == Op.insert ? null : adaptador.syncVersionOf(row),
    );
  }

  SyncTableAdapter<T> _adapterFor<T>(T row) {
    for (final adaptador in _adapters.values) {
      if (adaptador is SyncTableAdapter<T>) return adaptador;
    }
    throw StateError('no hay SyncTableAdapter registrado para $T. '
        'Pasalo en SyncEngine(adapters: [...])');
  }

  /// El adaptador de una entidad remota, si la app lo registró.
  SyncTableAdapter<Object?>? adapterOf(String entity) => _adapters[entity];

  /// Dispara ya lo que esté esperando la ventana de [criticalDebounce] y
  /// espera a que termine el ciclo.
  ///
  /// La app la llama cuando no puede esperar: al pasar a segundo plano, al
  /// cerrar la jornada. Los tests la usan en vez de dormir.
  Future<void> flush() async {
    _verificarVivo();
    if (_criticalTimer?.isActive ?? false) {
      _criticalTimer!.cancel();
      await trigger(SyncTrigger.criticalWrite);
    }
    await settled;
  }

  /// Sync manual (HU-SYNC-007). Corre **siempre**, incluso con ahorro de datos.
  Future<SyncOutcome> syncNow() {
    _verificarVivo();
    return _start(SyncTrigger.manual);
  }

  /// Un disparador automático (§5.2). No corre con ahorro de datos activo.
  Future<SyncOutcome> trigger(SyncTrigger trigger) => _start(trigger);

  /// La cola de error, para mostrarla (RF-SY06).
  ///
  /// Cada entrada trae el `code` con el que el backend la rechazó y el job
  /// entero, para que la app pueda mostrar de qué venta se trata. El `id` es lo
  /// que después va a [requeue].
  Future<List<QueuedJob>> errorQueue({int limit = 100}) =>
      _jobs.listInvalid(limit: limit);

  /// `INVALID` → `PENDING`, tras corregir el dato (§3).
  Future<void> requeue(String jobId) async {
    _verificarVivo();
    await _jobs.requeue(jobId);
    await _emit();
  }

  /// Saca jobs de la cola de error para siempre. Devuelve cuántos sacó.
  ///
  /// [requeue] es para el dato que se corrigió; este es para el que no tiene
  /// arreglo. Los dos hacen falta: sin descarte, un job cuyo payload el
  /// servidor va a rechazar siempre se queda en la cola y el contador rojo se
  /// vuelve permanente.
  ///
  /// Borra, no archiva. El job ya no subió y no va a subir: guardarlo en otro
  /// estado sería dejar la misma basura con otro nombre. Lo que se pierde es el
  /// intento, no el dato de negocio: la fila sigue en la DB local, y si el
  /// colportor la quiere mandar de nuevo se la vuelve a stagear corregida.
  Future<int> discard(Iterable<String> jobIds) async {
    _verificarVivo();
    final n = await _jobs.discardInvalid(jobIds);
    if (n > 0) await _emit();
    return n;
  }

  /// Ahorro de datos (HU-SYNC-008). Solo afecta a los ciclos automáticos:
  /// [syncNow] sigue funcionando.
  void setDataSaver(bool on) => _dataSaver = on;

  /// Recuperación de dispositivo: el colportor perdió el celular (§7).
  ///
  /// Sus datos están repartidos en dos lugares y ninguno solo alcanza: lo
  /// `local` (persona, nota) existe únicamente en el backup E2E de su Drive; lo
  /// `push` (ventas, cobranzas, visitas) vive en Supabase con lo último que
  /// alcanzó a subir. La recuperación es la fusión de las dos fuentes.
  ///
  /// Precondición, del lado de la app: login en el dispositivo nuevo, sesiones
  /// del viejo revocadas y DB cifrada inicializada. El motor recibe la DB vacía
  /// y el JWT.
  Future<RecoveryReport> recover() async {
    _verificarVivo();
    // Toma el mismo candado que los ciclos: si vuelve la red mientras el wizard
    // reconcilia, el trigger de conectividad no puede arrancar un pull en
    // paralelo sobre los mismos scopes y dejar el watermark en cualquier lado.
    while (_running != null) {
      await _running;
    }
    final candado = Completer<SyncOutcome>();
    _running = candado.future;
    try {
      return await _recuperar();
    } finally {
      _running = null;
      _correrPendiente();
      candado.complete(
        const SyncOutcome(trigger: SyncTrigger.manual, skipped: true),
      );
    }
  }

  Future<RecoveryReport> _recuperar() async {
    final ahora = _clock();
    BackupEntry? punta;
    DateTime? restauradoAntes;
    var problema = '';

    // Fase 1 — restore desde Drive.
    //
    // Se hace **una sola vez**. Si la red se corta en la fase 3, el wizard
    // muestra el error y el colportor toca "reintentar": volver a restaurar
    // pisaría la DB con el backup y se llevaría puesto el replay y la
    // reconciliación que sí habían terminado. La marca queda en la propia DB,
    // así que sobrevive a que se cierre la app en el medio.
    final yaRestaurado = await _store.watermarkOf(_scopeRecovery);

    if (yaRestaurado != null) {
      punta = null;
      restauradoAntes = DateTime.tryParse(yaRestaurado);
    } else if (_backup != null && await _backup.isAuthorized) {
      punta = await _backup.restore();
      if (punta == null) {
        final estado = await _backup.verifyChain();
        problema = estado.problems.map((p) => p.name).join(', ');
      } else {
        // El watermark que tenía la DB al momento del backup: desde ahí
        // arranca la reconciliación, no desde cero.
        await _store.applyDelta(
          const {},
          scope: _scopeMirror,
          watermark: punta.watermark,
        );
        await _store.applyDelta(
          const {},
          scope: _scopeRecovery,
          watermark: punta.createdAt.toIso8601String(),
        );
      }
    }

    // Fase 2 — replay de la cola restaurada.
    //
    // Es seguro aunque esos jobs ya se hubieran subido: el cache de
    // `client_op_id` puede haber vencido (TTL 24 h) pero las PK son UUID v7
    // del dispositivo original, así que un insert repetido vuelve
    // `duplicate`, no una segunda venta.
    final replay = punta == null ? null : await _pushPending();

    // Fase 3 — reconciliación: lo que subió después del backup.
    final reconciliadas = <String, int>{};
    await _pullInto(_scopeMirror, _specs.pushable, reconciliadas);

    // Fase 4 — catálogos: réplica fresca, no se restauran del backup.
    await _pullInto(_scopeReplica, _specs.replicaOnly, reconciliadas);
    resubscribe();

    _lastSuccessAt = _clock();
    await _emit();

    // En un reintento, la fecha sale de la marca: el reporte tiene que decir de
    // cuándo son los datos aunque el restore haya sido en el intento anterior.
    final fechaDelBackup = punta?.createdAt ?? restauradoAntes;
    return RecoveryReport(
      backupDate: fechaDelBackup,
      replayedJobs: replay?.pushed ?? 0,
      pulledEntities: reconciliadas,
      lostWindow: fechaDelBackup == null
          ? null
          : LostWindow(from: fechaDelBackup, to: ahora),
      chainProblem: problema,
    );
  }

  /// Purga de `DONE` a los 7 días (§5.8).
  Future<int> purge({Duration retention = const Duration(days: 7)}) =>
      _jobs.purgeDone(_clock().subtract(retention));

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _criticalTimer?.cancel();
    _realtimeTimer?.cancel();
    await _realtimeSub?.cancel();
    await _realtimePort?.unsubscribe();
    await _conn?.cancel();
    await _status.close();
  }

  // --- el ciclo ---------------------------------------------------------------

  /// Corre el trigger que se salteó, si hubo uno. Se llama al terminar
  /// cualquier cosa que tenía el candado.
  void _correrPendiente() {
    final trigger = _pendiente;
    if (trigger == null || _running != null) return;
    _pendiente = null;
    unawaited(_start(trigger));
  }

  /// Un burst de eventos se colapsa en un ciclo.
  ///
  /// Si ya hay uno corriendo, se marca la bandera y el que termina la vuelve a
  /// mirar: cincuenta cambios de precio seguidos son un pull, no cincuenta.
  Future<void> _drainRealtime() async {
    if (_running != null) return;
    while (_realtimePending) {
      _realtimePending = false;
      if (_dataSaver) return;
      await _start(SyncTrigger.realtime);
    }
  }

  void _verificarVivo() {
    if (_disposed) {
      throw StateError('este SyncEngine ya fue dispose()');
    }
  }

  Future<SyncOutcome> _start(SyncTrigger trigger) async {
    // Los caminos internos —un trigger pendiente que se libera, el debounce de
    // realtime— no tiran: simplemente no hacen nada.
    if (_disposed) return SyncOutcome(trigger: trigger, skipped: true);
    if (_dataSaver && trigger != SyncTrigger.manual) {
      return SyncOutcome(trigger: trigger, skipped: true);
    }

    // Un solo ciclo por vez: dos en paralelo se pisarían los jobs IN_FLIGHT y
    // podrían mandar el mismo dos veces.
    if (_running != null) {
      // Un trigger automático no insiste: lo que quedó pendiente ya está en
      // PENDING y sube en el ciclo que está corriendo o en el siguiente.
      if (trigger != SyncTrigger.manual) {
        _pendiente = trigger;
        return SyncOutcome(trigger: trigger, skipped: true);
      }
      // El manual sí: el colportor apretó el botón y tiene que pasar algo.
      // Esperar al ciclo en curso y correr uno propio es la diferencia entre
      // "sincronizado" y un botón que a veces no hace nada.
      while (_running != null) {
        await _running;
      }
    }

    final ciclo = _cycle(trigger).whenComplete(() {
      _running = null;
      _correrPendiente();
      if (_realtimePending) unawaited(_drainRealtime());
    });
    _running = ciclo;
    return ciclo;
  }

  Future<SyncOutcome> _cycle(SyncTrigger trigger) async {
    // §5.6: el evento solo dice que algo cambió allá. Subir la cola por eso
    // convertiría cada cambio de precio del administrador en tráfico de subida
    // desde todos los celulares a la vez.
    final subida = trigger == SyncTrigger.realtime
        ? (pushed: 0, invalidated: 0, conflicts: 0, failure: null)
        : await _pushPending();
    if (subida.failure != null) {
      _anotarSesion(subida.failure);
      await _emit();
      return SyncOutcome(
        trigger: trigger,
        pushed: subida.pushed,
        invalidated: subida.invalidated,
        conflicts: subida.conflicts,
        failure: subida.failure,
      );
    }

    final int pulled;
    try {
      pulled = await _pull(_scopeReplica, _specs.pullable);
    } on TransportFailure catch (falla) {
      _anotarSesion(falla);
      await _emit();
      return SyncOutcome(
        trigger: trigger,
        pushed: subida.pushed,
        invalidated: subida.invalidated,
        conflicts: subida.conflicts,
        failure: falla,
      );
    }

    _lastSuccessAt = _clock();
    _anotarSesion(null);
    await _emit();
    return SyncOutcome(
      trigger: trigger,
      pushed: subida.pushed,
      invalidated: subida.invalidated,
      conflicts: subida.conflicts,
      pulled: pulled,
    );
  }

  /// Vacía la cola hacia el backend. Es el corazón del ciclo y también la
  /// fase 2 de §7 (replay), que es el mismo trabajo sobre una cola restaurada.
  Future<
      ({
        int pushed,
        int invalidated,
        int conflicts,
        TransportFailure? failure
      })> _pushPending() async {
    var pushed = 0, invalidated = 0, conflicts = 0;

    // Lo que quedó colgado en vuelo vuelve a la cola. En **cada** ciclo y no
    // una vez por arranque: un job que se colgó con la app abierta ya no tiene
    // que esperar a que alguien la reinicie. Lo que evita llevarse puesto un
    // job que de verdad está viajando —acá o en el isolate de segundo plano—
    // es la antigüedad, no el momento en que se llama.
    await _jobs.reclaimInFlight(inFlightLease);

    final tomados = await _jobs.claimPending(limit: batchLimit);
    // Un mapa una vez por ciclo, en vez de recorrer la lista por cada
    // resultado: con lotes de 500 son 500 búsquedas de 500 elementos.
    final idPorOpId = {for (final q in tomados) q.job.clientOpId: q.id};

    // Todo lo que se tomó y todavía no se resolvió. Si algo revienta de una
    // forma que este código no previó —un bug del adaptador, un OOM—, estos
    // vuelven a PENDING antes de propagar: un job colgado en IN_FLIGHT es una
    // venta que no sube nunca más.
    final sinResolver = {for (final q in tomados) q.id};
    try {
      for (final lote in buildBatches(tomados)) {
        final PushResult resultado;
        try {
          resultado = await _transport.push(lote);
        } on TransportFailure catch (falla) {
          final ids = _idsDe(lote, idPorOpId);
          if (falla.kind == FailureKind.payload) {
            // El lote entero rebotó por su contenido: reintentarlo tal cual daría
            // el mismo error para siempre (§5.1).
            for (final id in ids) {
              await _jobs.markInvalid(id,
                  code: falla.code, message: falla.message);
              sinResolver.remove(id);
            }
            invalidated += ids.length;
            continue;
          }
          // Transitorio: vuelven a PENDING y el ciclo se corta acá. Lo que quedó
          // sin intentar ya está en PENDING, así que sube al próximo trigger.
          await _jobs.markPending(sinResolver);
          sinResolver.clear();
          return (
            pushed: pushed,
            invalidated: invalidated,
            conflicts: conflicts,
            failure: falla,
          );
        }

        final hechos = <String>[];
        for (final r in resultado.results) {
          final id = idPorOpId[r.clientOpId];
          if (id == null) continue;
          switch (r.outcome) {
            case JobOutcome.accepted:
            case JobOutcome.duplicate:
              hechos.add(id);
              pushed++;
            case JobOutcome.conflict:
              // §5.4: el servidor gana por sync_version. Se aplica su fila y el
              // job se cierra: no es un error del colportor, no va a la cola de
              // error.
              if (r.serverRow != null) {
                await _store.applyDelta(
                  {
                    _entidadDe(tomados, id): [r.serverRow!]
                  },
                  scope: _scopeMirror,
                  watermark: await _store.watermarkOf(_scopeMirror) ?? '',
                );
              }
              hechos.add(id);
              conflicts++;
            case JobOutcome.invalid:
              await _jobs.markInvalid(id, code: r.code, message: r.message);
              invalidated++;
          }
          sinResolver.remove(id);
        }
        if (hechos.isNotEmpty) await _jobs.markDone(hechos, at: _clock());
      }
    } on Object {
      if (sinResolver.isNotEmpty) await _jobs.markPending(sinResolver);
      rethrow;
    }

    return (
      pushed: pushed,
      invalidated: invalidated,
      conflicts: conflicts,
      failure: null,
    );
  }

  /// Baja el delta hasta agotarlo. El watermark solo avanza dentro de
  /// [LocalStorePort.applyDelta], que es una transacción: si aplicar falla, el
  /// próximo pull vuelve a traer lo mismo.
  Future<int> _pull(String scope, List<String> entities) async {
    if (entities.isEmpty) return 0;
    var traidas = 0;
    var watermark = await _store.watermarkOf(scope);

    while (true) {
      final delta =
          await _transport.pull(entities: entities, watermark: watermark);
      final filas = delta.rows.values.fold(0, (n, l) => n + l.length);
      if (filas > 0) {
        await _store.applyDelta(delta.rows,
            scope: scope, watermark: delta.watermark);
        traidas += filas;
      }
      // Si el watermark no avanzó, la próxima request es idéntica a esta: un
      // `has_more` que nunca baja es un bug del servidor, y un cliente que le
      // cree se queda pidiendo la misma página hasta quemarle los datos al
      // colportor.
      if (delta.watermark == watermark) return traidas;
      watermark = delta.watermark;
      if (!delta.hasMore) return traidas;
    }
  }

  /// Como [_pull], pero acumulando el conteo por entidad para el reporte de §7.
  Future<void> _pullInto(
    String scope,
    List<String> entities,
    Map<String, int> contador,
  ) async {
    if (entities.isEmpty) return;
    var watermark = await _store.watermarkOf(scope);

    while (true) {
      final delta =
          await _transport.pull(entities: entities, watermark: watermark);
      final filas = delta.rows.values.fold(0, (n, l) => n + l.length);
      if (filas > 0) {
        await _store.applyDelta(delta.rows,
            scope: scope, watermark: delta.watermark);
        for (final MapEntry(key: entidad, value: lista) in delta.rows.entries) {
          contador[entidad] = (contador[entidad] ?? 0) + lista.length;
        }
      }
      // Ver [_pull]: sin watermark nuevo no hay página nueva que pedir.
      if (delta.watermark == watermark) return;
      watermark = delta.watermark;
      if (!delta.hasMore) return;
    }
  }

  /// Lleva la cuenta de si la sesión sirve, para que un refresh roto no sea
  /// silencioso (B1).
  ///
  /// Solo un ciclo que funcionó limpia la marca. Una falla sin status —sin red,
  /// timeout— la deja como está a propósito: no saber si la sesión anda no es
  /// lo mismo que saber que anda, y limpiarla ahí haría que el aviso apareciera
  /// y desapareciera cada vez que el colportor entra y sale de cobertura.
  void _anotarSesion(TransportFailure? falla) {
    if (falla == null) {
      _sinSesionDesde = null;
    } else if (falla.status == 401) {
      // `??=`: interesa **desde cuándo**, no la última vez. Es el dato con el
      // que la app decide si molestar al colportor o esperar un poco más.
      _sinSesionDesde ??= _clock();
    }
  }

  Future<void> _emit() async {
    if (_status.isClosed) return;
    // Contar la cola cuesta una consulta a la DB. Hacerlo en cada `stage()`
    // convierte encolar 5.000 visitas de una semana sin red en 5.000 COUNT
    // sobre una tabla que crece. Si nadie está mirando el estado, no hay a
    // quién informarle.
    if (!_status.hasListener) return;
    final s = await _jobs.status();
    _status.add(SyncStatus(
      pending: s.pending,
      inFlight: s.inFlight,
      invalid: s.invalid,
      lastSuccessAt: _lastSuccessAt,
      unauthorizedSince: _sinSesionDesde,
    ));
  }

  // --- correspondencia entre lote y cola --------------------------------------

  static const _scopeReplica = 'replica';
  static const _scopeMirror = 'mirror';

  /// Marca de "el backup ya se restauró en este dispositivo". Vive en la DB
  /// local, no en memoria: un `recover()` interrumpido se retoma aunque la app
  /// se haya cerrado en el medio.
  static const _scopeRecovery = 'recovery';

  List<String> _idsDe(PushBatch lote, Map<String, String> idPorOpId) => [
        for (final job in lote.jobs)
          if (idPorOpId[job.clientOpId] case final id?) id,
      ];

  String _entidadDe(List<QueuedJob> tomados, String id) =>
      tomados.firstWhere((q) => q.id == id).job.entity;
}
