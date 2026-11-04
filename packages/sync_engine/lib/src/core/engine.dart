import 'dart:async';

import 'backup.dart';
import 'backup_service.dart';
import 'batch.dart';
import 'model.dart';
import 'ports.dart';
import 'queue.dart';
import 'adapter.dart';
import 'recover.dart';
import 'retenidas.dart';
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
    this.pausedReason,
    this.failure,
  });

  final SyncTrigger trigger;
  final int pushed;
  final int invalidated;
  final int conflicts;
  final int pulled;

  /// El ciclo no llegó a correr: ya había uno en curso, o el motor está apagado.
  final bool skipped;

  /// Por qué el ciclo subió pero **no bajó** el delta: [kDataSaverOnMobile]
  /// (HU-SYNC-008). El ciclo no falló —lo pendiente subió— y el pull espera a
  /// que haya Wi-Fi, a un sync manual o a un evento de realtime.
  final String? pausedReason;

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
    SyncMetaPort? meta,
    DateTime Function()? clock,
    UuidV7? uuid,
    this.batchLimit = 500,
    this.realtimeDebounce = const Duration(milliseconds: 300),
    this.criticalDebounce = const Duration(seconds: 2),
    this.inFlightLease = const Duration(minutes: 10),
  }) : _specs = specs,
       _uuid = uuid ?? UuidV7(),
       _adapters = {for (final a in adapters) a.remoteName: a},
       _backup = backup,
       _meta = meta,
       _connectivity = connectivity,
       _realtimePort = realtime,
       _transport = transport,
       _jobs = jobs,
       _store = store,
       _clock = clock ?? (() => DateTime.now().toUtc()) {
    if (connectivity != null) {
      _conn = connectivity.onlineChanges.listen((online) {
        if (online) trigger(SyncTrigger.connectivity);
      });
      // HU-SYNC-008: el pull que el ahorro de datos dejó esperando sale cuando
      // aparece un Wi-Fi. Pasar de datos móviles a Wi-Fi no cambia `online`.
      _wifiSub = connectivity.wifiChanges.listen((wifi) {
        if (wifi && _pullEnPausa != null) trigger(SyncTrigger.connectivity);
      });
    }
    // HU-SYNC-007: la fecha del último backup sale del propio servicio.
    _backup?.alTerminarUnBackup = (entrada) async {
      _ultimoBackup = entrada.createdAt;
      await _anotarMeta(lastBackupAt: entrada.createdAt);
      await _emit();
    };
    // El backup guarda el watermark de pull de la DB (§7 fase 3): la app llama
    // a `backup.backupNow()` sin saber qué es.
    _backup?.watermarkProvider = () => _store.watermarkOf(_scopeMirror);
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
  final SyncMetaPort? _meta;
  final ConnectivityPort? _connectivity;
  final DateTime Function() _clock;

  /// Backup E2E (§3, ADR-003). Lanza si el motor se armó sin los puertos de
  /// backup: es un error de cableado, no algo que la app deba atrapar.
  BackupService get backup =>
      _backup ??
      (throw StateError(
        'este SyncEngine se armó sin BackupService: '
        'faltan ArchivePort, CryptoPort y SnapshotPort',
      ));

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
  StreamSubscription<bool>? _wifiSub;
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
  DateTime? _ultimoPush;
  SyncNetwork? _ultimaRed;
  DateTime? _ultimoPull;
  DateTime? _ultimoBackup;

  /// Por qué el último ciclo dejó el pull esperando (HU-SYNC-008), o `null`.
  String? _pullEnPausa;

  /// Desde cuándo el backend contesta `401`. Ver [SyncStatus.unauthorizedSince].
  DateTime? _sinSesionDesde;

  /// Estado de la cola para la UI (§3). No emite hasta que algo cambia: quien
  /// abre la pantalla pide el estado de ahora con [statusNow] y sigue el flujo.
  Stream<SyncStatus> get status => _status.stream;

  /// El estado de ahora (HU-SYNC-007): conteos de la cola, última subida y
  /// última bajada, último backup y si el pull está en pausa por el ahorro de
  /// datos. Es lo primero que muestra la pantalla de estado, antes de que el
  /// flujo [status] emita algo.
  Future<SyncStatus> statusNow() async {
    _verificarVivo();
    return _foto();
  }

  /// El ciclo en curso, si hay uno. Los tests lo esperan en vez de dormir.
  Future<SyncOutcome> get settled =>
      _running ??
      Future.value(
        const SyncOutcome(trigger: SyncTrigger.manual, skipped: true),
      );

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

    final ahora = _clock();
    final job = SyncJob(
      clientOpId: clientOpId ?? _uuid.next(),
      entity: entity,
      op: op,
      payload: payload,
      syncVersion: syncVersion,
      createdAt: ahora,
      rowPk: payload[_specs.of(entity).pk]?.toString(),
    );

    // §2.2: si la fila tiene una escritura en espera, esta la reemplaza en vez
    // de encolarse aparte. Es como la app resuelve un conflicto (vista 10).
    final absorbido = op == Op.insert ? null : await _absorber(job);
    if (absorbido != null) {
      await _emit();
      // Resolver un conflicto es lo que la colportora estaba esperando para
      // que suba: no hay por qué esperar al próximo trigger.
      _programarCritico();
      return absorbido;
    }

    final fundido = op == Op.insert ? null : await _fundirEnPendiente(job);
    if (fundido != null) {
      await _emit();
      if (_specs.of(entity).critical) _programarCritico();
      return fundido;
    }

    final id = await _jobs.append(job);
    await _emit();

    if (_specs.of(entity).critical) _programarCritico();
    return id;
  }

  void _programarCritico() {
    _criticalTimer?.cancel();
    _criticalTimer = _zona.createTimer(criticalDebounce, () {
      unawaited(trigger(SyncTrigger.criticalWrite));
    });
  }

  /// La compactación de §2.2: [job] escribe una fila cuya escritura anterior
  /// quedó en espera. Devuelve el id del job que la absorbió, o `null` si no
  /// había nada en espera y hay que encolarlo como siempre.
  ///
  /// El servidor no tiene esa escritura anterior, así que no hay nada que
  /// ordenarle: la fila nueva la reemplaza, fundida sobre la vieja (un update
  /// que trae solo algunas columnas no borra las demás del alta). Lo que la
  /// escritura vieja tenía colgando vuelve a la cola con ella, detrás, para
  /// viajar en el mismo lote.
  ///
  /// Si [job] da de baja una fila que el servidor nunca tuvo (un `delete`, o un
  /// `deleted_at`), no se sube nada: el alta se descarta. Lo que colgaba de ella
  /// vuelve a la cola igual; si todavía la nombra, el servidor lo rechaza y
  /// queda `INVALID`, visible, en vez de esperar para siempre a una fila que ya
  /// no existe.
  Future<String?> _absorber(SyncJob job) async {
    final pk = pkDe(_specs, job);
    if (pk == null) return null;
    final enEspera = await _jobs.listHeld();
    if (enEspera.isEmpty) return null;

    // Todas las escrituras en espera de esta fila, de la más vieja a la más
    // nueva: un update que se mandó antes de que el alta chocara también quedó
    // esperándola, y fundirlo después de esta escritura la pisaría.
    final deLaFila = [
      for (final q in enEspera)
        if (q.job.entity == job.entity && pkDe(_specs, q.job) == pk) q,
    ];
    if (deLaFila.isEmpty) return null;

    final destino = deLaFila.first;
    final colgados = _colgadosDe(pk, enEspera, excepto: deLaFila);
    final ahora = job.createdAt;

    if (job.op == Op.delete && destino.job.op != Op.insert) {
      // La fila existe en el servidor y la corrección que esperaba ya no
      // importa: se descarta y el delete se encola como siempre.
      await _jobs.discardHeld([for (final q in deLaFila) q.id]);
      return null;
    }
    final baja = job.op == Op.delete || job.payload['deleted_at'] != null;
    if (baja && destino.job.op == Op.insert) {
      await _jobs.discardHeld([for (final q in deLaFila) q.id]);
      await _jobs.release([for (final q in colgados) q.id], at: ahora);
      return destino.id;
    }

    final fila = <String, Object?>{
      for (final q in deLaFila) ...q.job.payload,
      ...job.payload,
    };
    await _jobs.replacePayload(destino.id, fila);
    await _jobs.discardHeld([for (final q in deLaFila.skip(1)) q.id]);
    // B1: lo que cuelga de la fila y quedó `PENDING` (un espacio cargado sin
    // señal, antes de que ningún ciclo lo viera) tiene que salir detrás del
    // alta, no delante. Va con los que estaban esperando, en su orden.
    final sueltos = _pendientesQueCuelgan([
      destino,
      ...colgados,
    ], await _jobs.listPending());
    await _jobs.release([
      destino.id,
      for (final q in _enOrdenDeCreacion([...colgados, ...sueltos])) q.id,
    ], at: ahora);
    return destino.id;
  }

  /// [job] reescribe una fila que ya tiene una escritura `PENDING`, que todavía
  /// no salió: se funde en ella en vez de encolarse aparte. Devuelve el id del
  /// job que la absorbió, o `null` si no había ninguno.
  ///
  /// Dos escrituras de la misma fila en la cola son dos `sync_version`
  /// esperadas iguales (las dos se stagearon sobre la misma fila local), y en
  /// el servidor la segunda vuelve `conflict` (§5.4): el LWW la pisaría con la
  /// primera. Fundidas, sube una sola con la fila final. El job que absorbe
  /// conserva su `op` (un alta sigue siendo un alta) y su versión esperada.
  ///
  /// Un `delete` no se funde: se encola detrás y sale después.
  Future<String?> _fundirEnPendiente(SyncJob job) async {
    final pk = job.rowPk;
    if (job.op == Op.delete || pk == null) return null;
    final sinMandar = await _jobs.unsentFor(job.entity, pk);
    if (sinMandar.isEmpty) return null;
    final destino = sinMandar.last;
    if (destino.state != JobState.pending || destino.job.op == Op.delete) {
      return null;
    }
    final fundido = {...destino.job.payload, ...job.payload};
    await _jobs.replacePayload(destino.id, fundido);
    await _pasarDetrasDeLoQueNombra(destino, fundido, job.createdAt);
    return destino.id;
  }

  /// El payload fundido de [destino] puede nombrar una fila cuyo alta se
  /// encoló **después** de él: la agenda que se agenda y más tarde se cumple
  /// con una visita funde el cumplimiento en su alta, y ahora lleva `visita_id`
  /// aunque el alta de la visita viaje detrás. El servidor aplica el lote en
  /// orden y comprueba cada FK en el momento (`23503`): la agenda quedaba
  /// `INVALID` y la cita cumplida no subía nunca.
  ///
  /// Si pasa, [destino] se reubica detrás de esas altas, con lo que cuelga de
  /// él (el mismo criterio de [_absorber]). Si no nombra nada que vaya
  /// después, no se mueve: conserva su lugar en la cola.
  ///
  /// Solo cuentan las altas de entidades con PK propia (`id`): `house_status`
  /// se identifica con el id de la ubicación y nadie lo nombra, así que su PK
  /// no es una referencia posible (y confundiría a la ubicación con su propio
  /// color).
  Future<void> _pasarDetrasDeLoQueNombra(
    QueuedJob destino,
    Map<String, Object?> payload,
    DateTime ahora,
  ) async {
    final pendientes = await _jobs.listPending();
    final lugar = pendientes.indexWhere((q) => q.id == destino.id);
    if (lugar < 0) return;
    final propia = _specs.of(destino.job.entity).pk;
    final detras = <String>{};
    for (final q in pendientes.skip(lugar + 1)) {
      if (q.job.op != Op.insert || _specs.of(q.job.entity).pk != 'id') continue;
      if (pkDe(_specs, q.job) case final pk?) detras.add(pk);
    }
    if (detras.isEmpty) return;
    final nombra = payload.entries.any(
      (e) => e.key != propia && e.value is String && detras.contains(e.value),
    );
    if (!nombra) return;
    final cuelgan = _pendientesQueCuelgan([destino], pendientes);
    await _jobs.release([
      destino.id,
      for (final q in _enOrdenDeCreacion(cuelgan)) q.id,
    ], at: ahora);
  }

  /// Las `sync_version` que el servidor les dio a las filas de un lote vuelven
  /// a las filas locales y a lo que de esas filas espera en la cola (§5.4).
  /// [versiones] va de entidad a `rowPk` → versión.
  ///
  /// Sin esto el próximo `update` de una fila espera la versión de antes,
  /// vuelve `conflict` y el LWW pisa la edición: cerrar una jornada que ya
  /// subió la reabriría en el teléfono. Va una vez por entidad y por lote, no
  /// por fila: con 20.000 jobs, una consulta por fila es la diferencia entre
  /// subir en segundos y en minutos.
  Future<void> _devolverVersiones(
    Map<String, Map<String, int>> versiones,
  ) async {
    for (final MapEntry(key: entidad, value: porFila) in versiones.entries) {
      await _store.applyVersions(
        entidad,
        pkColumn: _specs.of(entidad).pk,
        versionPorFila: porFila,
      );
      await _jobs.rebaseVersions(entidad, porFila);
    }
  }

  /// Los `PENDING` de [pendientes] que nombran una fila de [liberados] (la regla
  /// de [FilasRetenidas]: como PK o como referencia), o algo que a su vez
  /// cuelga de ellos. Son los que `release` tiene que pasar detrás del alta: si
  /// quedaran delante, saldrían en el lote antes de la fila que nombran y el
  /// servidor los rechazaría con `23503` en vez de dejarlos en espera (§2.2).
  List<QueuedJob> _pendientesQueCuelgan(
    List<QueuedJob> liberados,
    List<QueuedJob> pendientes,
  ) {
    if (pendientes.isEmpty) return const [];
    final retenidas = FilasRetenidas.de(_specs, liberados);
    final propios = {for (final q in liberados) q.id};
    final cuelgan = <String>{};
    var crecio = true;
    while (crecio) {
      crecio = false;
      for (final q in pendientes) {
        if (propios.contains(q.id) || cuelgan.contains(q.id)) continue;
        if (retenidas.nombrada(q.job) == null) continue;
        cuelgan.add(q.id);
        retenidas.retener(q.job);
        crecio = true;
      }
    }
    return [
      for (final q in pendientes)
        if (cuelgan.contains(q.id)) q,
    ];
  }

  /// [jobs] por `createdAt`, con el orden en que vinieron como desempate
  /// (`List.sort` no es estable).
  List<QueuedJob> _enOrdenDeCreacion(List<QueuedJob> jobs) {
    final conPosicion = [for (final (i, q) in jobs.indexed) (i, q)];
    conPosicion.sort((a, b) {
      final porFecha = a.$2.job.createdAt.compareTo(b.$2.job.createdAt);
      return porFecha != 0 ? porFecha : a.$1.compareTo(b.$1);
    });
    return [for (final (_, q) in conPosicion) q];
  }

  /// Lo que cuelga, directa o indirectamente, de la fila [pk]: los `WAITING`
  /// cuyo `dependsOn` es ella, o una fila que a su vez cuelga de ella. En orden
  /// de creación.
  List<QueuedJob> _colgadosDe(
    String pk,
    List<QueuedJob> enEspera, {
    required List<QueuedJob> excepto,
  }) {
    final fuera = {for (final q in excepto) q.id};
    final filas = {pk};
    final colgados = <String>{};
    var crecio = true;
    while (crecio) {
      crecio = false;
      for (final q in enEspera) {
        if (q.state != JobState.waiting ||
            fuera.contains(q.id) ||
            colgados.contains(q.id) ||
            !filas.contains(q.dependsOn)) {
          continue;
        }
        colgados.add(q.id);
        if (pkDe(_specs, q.job) case final propia?) filas.add(propia);
        crecio = true;
      }
    }
    return [
      for (final q in enEspera)
        if (colgados.contains(q.id)) q,
    ];
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
      _realtimeTimer = _zona.createTimer(
        realtimeDebounce,
        () => unawaited(_drainRealtime()),
      );
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
    throw StateError(
      'no hay SyncTableAdapter registrado para $T. '
      'Pasalo en SyncEngine(adapters: [...])',
    );
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

  /// Sync manual (HU-SYNC-007): push y pull inmediatos. Corre **siempre**,
  /// incluso con ahorro de datos y con datos móviles.
  Future<SyncOutcome> syncNow() {
    _verificarVivo();
    return _start(SyncTrigger.manual);
  }

  /// Un disparador automático (§5.2). Con el ahorro de datos activo y solo
  /// datos móviles sube igual, pero deja el pull para el Wi-Fi ([setDataSaver]).
  Future<SyncOutcome> trigger(SyncTrigger trigger) => _start(trigger);

  /// La cola de error, para mostrarla (RF-SY06).
  ///
  /// Cada entrada trae el `code` con el que el backend la rechazó y el job
  /// entero, para que la app pueda mostrar de qué venta se trata. El `id` es lo
  /// que después va a [requeue].
  Future<List<QueuedJob>> errorQueue({int limit = 100}) =>
      _jobs.listInvalid(limit: limit);

  /// Las operaciones que el servidor rechazó, para el «Ver detalle» de la
  /// pantalla de estado (HU-SYNC-007): tabla, fecha, tipo y el último error,
  /// **sin datos personales** (ni el payload ni los valores que el servidor
  /// cita en su mensaje; ver [sanitizarError]).
  ///
  /// Del más reciente al más viejo. Para el payload entero, [errorQueue].
  Future<List<FailedOperation>> failedOperations({int limit = 100}) async {
    final fallidas = await _jobs.listInvalid(limit: limit);
    return [
      for (final q in fallidas)
        FailedOperation(
          jobId: q.id,
          entity: q.job.entity,
          op: q.job.op,
          createdAt: q.job.createdAt,
          code: q.code,
          lastError: sanitizarError(q.message),
        ),
    ];
  }

  /// Lo que está en espera (§2.2), en orden de creación: las escrituras que el
  /// servidor no aplicó por un conflicto ([JobState.blocked]) y lo que cuelga
  /// de ellas ([JobState.waiting]).
  ///
  /// La app lo usa para la vista 10: un `blocked` con `code` `23505` es una
  /// ubicación a resolver. No hay `requeue` para esto: se resuelve volviendo a
  /// escribir la fila con [stage], y eso devuelve a la cola la escritura y todo
  /// lo que colgaba de ella.
  Future<List<QueuedJob>> heldQueue() => _jobs.listHeld();

  /// `INVALID` → `PENDING`, tras corregir el dato (§3).
  Future<void> requeue(String jobId) async {
    _verificarVivo();
    await _jobs.requeue(jobId);
    await _emit();
  }

  /// «Reintentar todas las fallidas» (HU-SYNC-007): `INVALID` → `PENDING` para
  /// todas. Devuelve cuántas reencoló. No dispara un ciclo: la pantalla sigue
  /// con [syncNow], así el colportor ve el resultado de ese intento.
  ///
  /// Una que el servidor vuelva a rechazar vuelve a la cola de error con su
  /// motivo; nada se pierde ni se reintenta solo.
  Future<int> requeueAllInvalid() async {
    _verificarVivo();
    // De a páginas: reencolar saca de `INVALID` lo que se acaba de leer, así
    // que la página siguiente es la que sigue. El tope es lo que había al
    // empezar: lo que el servidor rechace mientras tanto no entra en esta vuelta.
    final total = (await _jobs.status()).invalid;
    var n = 0;
    while (n < total) {
      final pagina = await _jobs.listInvalid(limit: 200);
      if (pagina.isEmpty) break;
      for (final q in pagina) {
        await _jobs.requeue(q.id);
      }
      n += pagina.length;
    }
    if (n > 0) await _emit();
    return n;
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

  /// Ahorro de datos (HU-SYNC-008). Solo afecta al batch, y dentro del batch,
  /// solo a **bajar**:
  ///
  /// - Con datos móviles, el delta (el «pull periódico» de cualquier ciclo
  ///   automático) espera a que haya Wi-Fi. El ciclo no falla: sube lo pendiente
  ///   y lo deja dicho en [SyncOutcome.pausedReason] y en
  ///   [SyncStatus.pullPausedReason] (`data_saver_on_mobile`).
  /// - **Lo que sube no se frena**: una venta, un cobro o una jornada salen por
  ///   datos móviles igual que antes, en el mismo ciclo.
  /// - Realtime sigue activo (es liviano) y [syncNow] corre siempre.
  /// - El backup automático pide Wi-Fi: ver [automaticBackupAllowed].
  void setDataSaver(bool on) {
    _dataSaver = on;
    // La pantalla de estado muestra el modo y, si hay un pull en pausa, el motivo.
    unawaited(_emit().catchError((Object _) {}));
  }

  /// El ahorro de datos está activo (HU-SYNC-008).
  bool get dataSaver => _dataSaver;

  /// Si el backup **automático** (el de la noche, el del cierre de jornada)
  /// puede correr ahora: con el ahorro de datos activo exige Wi-Fi
  /// (HU-SYNC-008). Quien lo agenda lo consulta antes de llamar a
  /// `backup.backupNow()`. El backup que el colportor pide a mano no pasa por
  /// acá: lo pidió, y la pantalla le avisa del peso.
  Future<bool> automaticBackupAllowed() async =>
      !_dataSaver || await _estaEnWifi();

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

    _lastSuccessAt = _ultimoPull = _clock();
    await _anotarMeta(lastPullAt: _ultimoPull);
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
    await _wifiSub?.cancel();
    _backup?.alTerminarUnBackup = null;
    _backup?.watermarkProvider = null;
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

    // Con la subida hecha, la fecha del último envío se actualiza sola: sale de
    // los jobs que el servidor confirmó (`DONE`). Lo que sí se decide acá es si
    // este ciclo baja el delta (HU-SYNC-008).
    if (await _pausaDelPull(trigger) case final motivo?) {
      _pullEnPausa = motivo;
      await _emit();
      return SyncOutcome(
        trigger: trigger,
        pushed: subida.pushed,
        invalidated: subida.invalidated,
        conflicts: subida.conflicts,
        pausedReason: motivo,
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

    _lastSuccessAt = _ultimoPull = _clock();
    await _anotarMeta(lastPullAt: _ultimoPull);
    _pullEnPausa = null;
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

  /// HU-SYNC-008: con el ahorro de datos activo y solo datos móviles, el ciclo
  /// automático **no baja** el delta y devuelve el motivo.
  ///
  /// No aplica al sync manual (el colportor lo pidió), al realtime (es liviano:
  /// un evento, un delta chico) ni a un teléfono sin red: ahí el pull falla como
  /// siempre, y llamar «ahorro de datos» a eso mentiría sobre el motivo.
  Future<String?> _pausaDelPull(SyncTrigger trigger) async {
    if (!_dataSaver ||
        trigger == SyncTrigger.manual ||
        trigger == SyncTrigger.realtime) {
      return null;
    }
    final red = _connectivity;
    if (red == null) return null;
    if (!await red.isOnline || await red.isOnWifi) return null;
    return kDataSaverOnMobile;
  }

  /// Con qué red sale un envío, o `null` si no se sabe: sin puerto de
  /// conectividad, sin red o si el puerto falla. Nunca se inventa un Wi-Fi: la
  /// vista dice «por datos» solo cuando lo sabe, y no por eso se cae un envío.
  Future<SyncNetwork?> _redActual() async {
    final red = _connectivity;
    if (red == null) return null;
    try {
      if (!await red.isOnline) return null;
      return await red.isOnWifi ? SyncNetwork.wifi : SyncNetwork.mobile;
    } on Object {
      return null;
    }
  }

  /// Anota en el teléfono lo que la pantalla de estado muestra después de
  /// reiniciar (HU-SYNC-007). Si la DB local falla no pasa nada grave: la
  /// bajada, el respaldo o el envío ya están hechos y el dato sigue en memoria;
  /// lo único que se pierde es acordarse de ellos tras cerrar la app.
  Future<void> _anotarMeta({
    DateTime? lastPullAt,
    DateTime? lastBackupAt,
    DateTime? lastPushAt,
    SyncNetwork? lastPushNetwork,
  }) async {
    final meta = _meta;
    if (meta == null) return;
    try {
      await meta.write(
        lastPullAt: lastPullAt,
        lastBackupAt: lastBackupAt,
        lastPushAt: lastPushAt,
        lastPushNetwork: lastPushNetwork,
      );
    } on Object {
      // Ver arriba.
    }
  }

  /// Lo que quedó anotado en el teléfono. Sin puerto, o si falla la lectura,
  /// no hay nada: el estado sale solo de lo que sabe el motor en memoria.
  Future<SyncMeta> _leerMeta() async {
    final meta = _meta;
    if (meta == null) return const SyncMeta();
    try {
      return await meta.read();
    } on Object {
      return const SyncMeta();
    }
  }

  /// Sin puerto de conectividad no hay forma de saber que es un dato móvil: se
  /// asume Wi-Fi, que es el comportamiento de antes del ahorro de datos.
  Future<bool> _estaEnWifi() async {
    final red = _connectivity;
    return red == null || await red.isOnWifi;
  }

  /// Vacía la cola hacia el backend. Es el corazón del ciclo y también la
  /// fase 2 de §7 (replay), que es el mismo trabajo sobre una cola restaurada.
  Future<
    ({int pushed, int invalidated, int conflicts, TransportFailure? failure})
  >
  _pushPending() async {
    var pushed = 0, invalidated = 0, conflicts = 0;

    // Lo que quedó colgado en vuelo vuelve a la cola. En **cada** ciclo y no
    // una vez por arranque: un job que se colgó con la app abierta ya no tiene
    // que esperar a que alguien la reinicie. Lo que evita llevarse puesto un
    // job que de verdad está viajando —acá o en el isolate de segundo plano—
    // es la antigüedad, no el momento en que se llama.
    await _jobs.reclaimInFlight(inFlightLease);

    final tomados = await _jobs.claimPending(limit: batchLimit);
    // La red por la que sale este envío, mirada antes de mandar (HU-SYNC-007).
    final red = tomados.isEmpty ? null : await _redActual();
    // Un mapa una vez por ciclo, en vez de recorrer la lista por cada
    // resultado: con lotes de 500 son 500 búsquedas de 500 elementos.
    final idPorOpId = {for (final q in tomados) q.job.clientOpId: q.id};
    final jobPorId = {for (final q in tomados) q.id: q.job};

    // §2.2: lo que el servidor no tiene. Crece a medida que los lotes vuelven
    // con conflictos, para que lo que cuelga de ellos no salga en un lote
    // posterior sin la fila que nombra.
    final retenidas = tomados.isEmpty
        ? FilasRetenidas(_specs)
        : FilasRetenidas.de(_specs, await _jobs.listHeld());

    // §5.4: la versión que devuelve un lote, para los lotes que siguen en este
    // ciclo. Sus jobs ya están tomados con la versión de antes; sin esto, una
    // segunda escritura de la misma fila (que buildBatches manda en otro lote)
    // saldría esperando una versión que el servidor ya no tiene.
    final versionVista = <(String, String), int>{};

    // Todo lo que se tomó y todavía no se resolvió. Si algo revienta de una
    // forma que este código no previó —un bug del adaptador, un OOM—, estos
    // vuelven a PENDING antes de propagar: un job colgado en IN_FLIGHT es una
    // venta que no sube nunca más.
    final sinResolver = {for (final q in tomados) q.id};
    try {
      for (final armado in buildBatches(tomados)) {
        final lote = _conVersionVista(
          await _sinLoQueEspera(armado, retenidas, idPorOpId),
          versionVista,
        );
        // Lo que se retuvo ya no está en vuelo: quedó WAITING.
        final salen = {for (final job in lote.jobs) job.clientOpId};
        for (final job in armado.jobs) {
          if (!salen.contains(job.clientOpId)) {
            sinResolver.remove(idPorOpId[job.clientOpId]);
          }
        }
        if (lote.isEmpty) continue;

        final PushResult resultado;
        try {
          resultado = await _transport.push(lote);
        } on TransportFailure catch (falla) {
          final ids = _idsDe(lote, idPorOpId);
          if (falla.kind == FailureKind.payload) {
            // El lote entero rebotó por su contenido: reintentarlo tal cual daría
            // el mismo error para siempre (§5.1).
            for (final id in ids) {
              await _jobs.markInvalid(
                id,
                code: falla.code,
                message: falla.message,
              );
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

        final hechos = <String>{};
        final versiones = <String, Map<String, int>>{};
        try {
          for (final r in resultado.results) {
            final id = idPorOpId[r.clientOpId];
            if (id == null) continue;
            switch (r.outcome) {
              case JobOutcome.accepted:
              case JobOutcome.duplicate:
                final job = jobPorId[id]!;
                // También la de un `delete`: la baja de esta app es lógica (`deleted_at`), la
                // fila sigue en el teléfono y, si se reactiva, su próximo `update` tiene que
                // salir con la versión que dejó la baja. Si la fila ya no está (baja física),
                // `applyVersions` la saltea.
                if ((r.syncVersion, job.rowPk) case (final v?, final pk?)) {
                  (versiones[job.entity] ??= {})[pk] = v;
                }
                hechos.add(id);
                pushed++;
              case JobOutcome.conflict when r.serverRow != null:
                // §5.4: el servidor gana por sync_version. Se aplica su fila y el
                // job se cierra: no es un error del colportor, no va a la cola de
                // error.
                await _store.applyDelta(
                  {
                    _entidadDe(tomados, id): [r.serverRow!],
                  },
                  scope: _scopeMirror,
                  // M1: la fila del servidor se aplica sin tocar el watermark.
                  // Guardar `''` si no había ninguno rompe la fase 3 de
                  // `recover()`: el backend contesta 22023 a un watermark vacío.
                  watermark: null,
                );
                hechos.add(id);
                conflicts++;
              case JobOutcome.conflict:
                // §2.2: sin server_row no hay con qué resolver. El servidor no
                // guardó la fila y la colportora la resuelve en la vista 10; lo
                // que cuelga de ella espera. Ninguno se cierra: un DONE acá es
                // una venta que no sube nunca.
                final dependeDe = r.dependsOn ?? '';
                if (r.code == kCodigoEsperaAltaEnConflicto &&
                    dependeDe.isNotEmpty) {
                  await _jobs.markWaiting(
                    id,
                    dependsOn: dependeDe,
                    code: r.code,
                    message: r.message,
                  );
                } else {
                  // Una espera sin depends_on no dice qué esperar: si quedara
                  // WAITING, nada la liberaría. BLOCKED, por lo menos, se ve.
                  await _jobs.markBlocked(id, code: r.code, message: r.message);
                }
                retenidas.retener(jobPorId[id]!);
                conflicts++;
              case JobOutcome.invalid:
                await _jobs.markInvalid(id, code: r.code, message: r.message);
                invalidated++;
            }
            if (!hechos.contains(id)) sinResolver.remove(id);
          }
        } finally {
          // M2: lo que el servidor ya aceptó se cierra aunque un conflicto de
          // más abajo haga reventar aplicar su fila (una DB local que falla).
          // Si no, esos jobs quedarían `IN_FLIGHT` hasta el lease y su
          // `sync_version` no volvería a las filas ni a la cola: una edición
          // nueva de la misma fila saldría con la versión vieja.
          await _devolverVersiones(versiones);
          for (final MapEntry(key: entidad, value: porFila)
              in versiones.entries) {
            for (final MapEntry(key: pk, value: v) in porFila.entries) {
              versionVista[(entidad, pk)] = v;
            }
          }
          if (hechos.isNotEmpty) {
            final ahora = _clock();
            await _jobs.markDone(hechos, at: ahora);
            _ultimoPush = ahora;
            _ultimaRed = red;
            await _anotarMeta(lastPushAt: ahora, lastPushNetwork: red);
            sinResolver.removeAll(hechos);
          }
        }
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

  /// [lote] con la `sync_version` que el servidor devolvió en este mismo
  /// ciclo para cada fila que ya viajó (ver `versionVista` en
  /// [_pushPending]). Las altas no esperan versión.
  PushBatch _conVersionVista(
    PushBatch lote,
    Map<(String, String), int> versionVista,
  ) {
    if (versionVista.isEmpty) return lote;
    var cambio = false;
    final jobs = <SyncJob>[];
    for (final job in lote.jobs) {
      final pk = job.rowPk;
      final vista = pk == null ? null : versionVista[(job.entity, pk)];
      if (job.op == Op.insert || vista == null || vista == job.syncVersion) {
        jobs.add(job);
      } else {
        jobs.add(job.copyWith(syncVersion: vista));
        cambio = true;
      }
    }
    return cambio ? PushBatch(jobs) : lote;
  }

  /// [lote] sin lo que nombra una fila retenida, que pasa a `WAITING` sin
  /// salir (§2.2). Si viajara, el servidor no lo podría aplicar: la fila no
  /// existe allá, y como el alta que la crea no va en este lote, no lo deja en
  /// espera sino `INVALID`.
  Future<PushBatch> _sinLoQueEspera(
    PushBatch lote,
    FilasRetenidas retenidas,
    Map<String, String> idPorOpId,
  ) async {
    if (retenidas.isEmpty) return lote;
    final salen = <SyncJob>[];
    for (final job in lote.jobs) {
      final fila = retenidas.nombrada(job);
      if (fila == null) {
        salen.add(job);
        continue;
      }
      await _jobs.markWaiting(idPorOpId[job.clientOpId]!, dependsOn: fila);
      // En cascada: lo que nombre a esta fila más adelante también espera.
      retenidas.retener(job);
    }
    return salen.length == lote.length ? lote : PushBatch(salen);
  }

  /// Baja el delta hasta agotarlo. El watermark solo avanza dentro de
  /// [LocalStorePort.applyDelta], que es una transacción: si aplicar falla, el
  /// próximo pull vuelve a traer lo mismo.
  Future<int> _pull(String scope, List<String> entities) async {
    if (entities.isEmpty) return 0;
    var traidas = 0;
    var watermark = await _store.watermarkOf(scope);

    while (true) {
      final delta = await _transport.pull(
        entities: entities,
        watermark: watermark,
      );
      final filas = delta.rows.values.fold(0, (n, l) => n + l.length);
      if (filas > 0) {
        await _store.applyDelta(
          delta.rows,
          scope: scope,
          watermark: delta.watermark,
        );
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
      final delta = await _transport.pull(
        entities: entities,
        watermark: watermark,
      );
      final filas = delta.rows.values.fold(0, (n, l) => n + l.length);
      if (filas > 0) {
        await _store.applyDelta(
          delta.rows,
          scope: scope,
          watermark: delta.watermark,
        );
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
    final foto = await _foto();
    if (_status.isClosed) return;
    _status.add(foto);
  }

  /// El estado de ahora: lo que cuenta la cola más lo que sabe el motor.
  Future<SyncStatus> _foto() async {
    final s = await _jobs.status();
    final meta = await _leerMeta();
    // El envío anotado más nuevo, de memoria o del teléfono, con su red.
    final (anotadoAt, anotadaRed) = switch ((_ultimoPush, meta.lastPushAt)) {
      (final m?, final d?) when d.isAfter(m) => (d, meta.lastPushNetwork),
      (final m?, _) => (m, _ultimaRed),
      (null, final d?) => (d, meta.lastPushNetwork),
      (null, null) => (null, null),
    };
    // El último envío se acuerda de los `DONE` de la cola (sobrevive a cerrar
    // la app); el de memoria cubre un store que no lo sabe contar.
    final ultimoPush = _masNuevo(anotadoAt, s.lastPushAt);
    // Si la cola sabe de un envío más nuevo que el anotado (uno de antes de que
    // el motor anotara la red), la red del anotado no es la de ese: no se sabe.
    final redDelEnvio =
        anotadoAt != null && (s.lastPushAt?.isAfter(anotadoAt) ?? false)
        ? null
        : anotadaRed;
    return SyncStatus(
      pending: s.pending,
      inFlight: s.inFlight,
      invalid: s.invalid,
      blocked: s.blocked,
      waiting: s.waiting,
      lastSuccessAt: _lastSuccessAt,
      lastPushAt: ultimoPush,
      lastPullAt: _masNuevo(_ultimoPull, meta.lastPullAt),
      lastBackupAt: _masNuevo(_ultimoBackup, meta.lastBackupAt),
      lastPushNetwork: redDelEnvio,
      pullPausedReason: _dataSaver ? _pullEnPausa : null,
      dataSaver: _dataSaver,
      unauthorizedSince: _sinSesionDesde,
    );
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

DateTime? _masNuevo(DateTime? a, DateTime? b) => switch ((a, b)) {
  (final x?, final y?) => x.isAfter(y) ? x : y,
  (final x?, null) => x,
  (null, final y) => y,
};
