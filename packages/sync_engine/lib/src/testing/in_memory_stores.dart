import '../core/model.dart';
import '../core/ports.dart';
import '../core/queue.dart';

/// `sync_queue` en memoria.
///
/// Se porta como la implementación Drift en lo único que el motor puede
/// observar: los `PENDING` salen en orden de creación y los `INVALID` no
/// vuelven solos.
class InMemoryJobStore implements JobStorePort {
  InMemoryJobStore({DateTime Function()? clock})
      : _clock = clock ?? (() => DateTime.now().toUtc());

  final DateTime Function() _clock;

  /// Indexada por id y en orden de llegada: un Map de Dart conserva el orden de
  /// inserción, así que sirve para las dos cosas. Con una lista, cada `byId`
  /// recorría la cola entera y subir 20.000 jobs se volvía cuadrático.
  final Map<String, QueuedJob> _jobs = {};

  /// Contadores incrementales. `status()` se llama seguido; contar la cola
  /// entera cada vez es justo lo que hace lento a un store.
  final Map<JobState, int> _cuenta = {for (final e in JobState.values) e: 0};

  int _n = 0;

  /// Cuándo se cerró el último job (`SyncStatus.lastPushAt`). Incremental, como
  /// los contadores.
  DateTime? _ultimoDone;

  /// Orden de llegada de cada job: el desempate de [_enOrden].
  final Map<String, int> _llegada = {};

  /// `entidad` + `rowPk` → ids de sus jobs, para [unsentFor] y [rebaseUnsent]
  /// sin recorrer la cola: se llaman en cada `stage()` de un update y por cada
  /// lote que vuelve.
  final Map<(String, String), List<String>> _porFila = {};

  /// Todo lo que hay en la cola, en orden de llegada.
  List<QueuedJob> get all => List.unmodifiable(_jobs.values);

  List<QueuedJob> withState(JobState state) => [
        for (final j in _jobs.values)
          if (j.state == state) j
      ];

  QueuedJob byId(String id) =>
      _jobs[id] ?? (throw StateError('no existe el job $id'));

  @override
  Future<String> append(SyncJob job) async {
    final id = 'job-${++_n}';
    _jobs[id] = QueuedJob(id: id, job: job, state: JobState.pending);
    _llegada[id] = _n;
    if (job.rowPk case final pk?) (_porFila[(job.entity, pk)] ??= []).add(id);
    _cuenta[JobState.pending] = _cuenta[JobState.pending]! + 1;
    return id;
  }

  @override
  Future<List<QueuedJob>> claimPending({int limit = 500}) async {
    final tomados = <QueuedJob>[];
    // §5.5: orden de creación. La lista ya está en ese orden porque append
    // agrega al final; ordenar explícito deja el invariante escrito.
    final candidatos =
        _enOrden([..._jobs.values.where((j) => j.state == JobState.pending)]);

    final ahora = _clock();
    for (final job in candidatos.take(limit)) {
      _reemplazar(job.copyWith(state: JobState.inFlight, claimedAt: ahora));
      tomados.add(job);
    }
    return tomados;
  }

  @override
  Future<void> markDone(Iterable<String> jobIds, {required DateTime at}) async {
    for (final id in jobIds) {
      _reemplazar(byId(id).copyWith(state: JobState.done, doneAt: at));
    }
    if (jobIds.isNotEmpty &&
        (_ultimoDone == null || at.isAfter(_ultimoDone!))) {
      _ultimoDone = at;
    }
  }

  @override
  Future<void> markInvalid(String jobId,
      {required String code, String message = ''}) async {
    _reemplazar(byId(jobId)
        .copyWith(state: JobState.invalid, code: code, message: message));
  }

  @override
  Future<void> markPending(Iterable<String> jobIds) async {
    for (final id in jobIds) {
      _reemplazar(
          byId(id).copyWith(state: JobState.pending, limpiarClaimedAt: true));
    }
  }

  @override
  Future<void> requeue(String jobId) async {
    _reemplazar(
        byId(jobId).copyWith(state: JobState.pending, code: '', message: ''));
  }

  @override
  Future<void> markBlocked(String jobId,
      {required String code, String message = ''}) async {
    _reemplazar(byId(jobId).copyWith(
        state: JobState.blocked,
        code: code,
        message: message,
        limpiarClaimedAt: true));
  }

  @override
  Future<void> markWaiting(String jobId,
      {required String dependsOn,
      String code = '',
      String message = ''}) async {
    _reemplazar(byId(jobId).copyWith(
        state: JobState.waiting,
        code: code,
        message: message,
        dependsOn: dependsOn,
        limpiarClaimedAt: true));
  }

  @override
  Future<List<QueuedJob>> listHeld() async => _enOrden([
        for (final j in _jobs.values)
          if (j.state == JobState.blocked || j.state == JobState.waiting) j
      ]);

  @override
  Future<List<QueuedJob>> listPending() async => _enOrden([
        for (final j in _jobs.values)
          if (j.state == JobState.pending) j
      ]);

  @override
  Future<void> replacePayload(
      String jobId, Map<String, Object?> payload) async {
    final q = _sinMandar(jobId, 'replacePayload');
    _reemplazar(q.copyWith(job: q.job.copyWith(payload: payload)));
  }

  @override
  Future<List<QueuedJob>> unsentFor(String entity, String rowPk) async =>
      _enOrden([
        for (final id in _porFila[(entity, rowPk)] ?? const <String>[])
          if (_jobs[id] case final j? when _esSinMandar(j.state)) j
      ]);

  @override
  Future<void> rebaseVersions(
      String entity, Map<String, int> versionPorFila) async {
    for (final MapEntry(key: pk, value: version) in versionPorFila.entries) {
      for (final id in _porFila[(entity, pk)] ?? const <String>[]) {
        final q = _jobs[id];
        if (q == null ||
            q.job.op == Op.insert ||
            q.state == JobState.done ||
            q.state == JobState.invalid) {
          continue;
        }
        _reemplazar(q.copyWith(job: q.job.copyWith(syncVersion: version)));
      }
    }
  }

  static bool _esSinMandar(JobState s) =>
      s == JobState.pending || s == JobState.blocked || s == JobState.waiting;

  QueuedJob _sinMandar(String jobId, String operacion) {
    final q = byId(jobId);
    if (!_esSinMandar(q.state)) {
      throw StateError('$operacion sobre un job en ${q.state.name}');
    }
    return q;
  }

  @override
  Future<void> release(List<String> jobIds, {required DateTime at}) async {
    // Detrás de todo: un microsegundo después del último createdAt de la cola,
    // o de [at] si es más tarde, y uno más por cada job, para que el orden de
    // [jobIds] sea el del claim.
    var base = at;
    for (final j in _jobs.values) {
      if (!j.job.createdAt.isBefore(base)) {
        base = j.job.createdAt.add(const Duration(microseconds: 1));
      }
    }
    var i = 0;
    for (final id in jobIds) {
      final q = _jobs[id];
      if (q == null ||
          (q.state != JobState.blocked &&
              q.state != JobState.waiting &&
              q.state != JobState.pending)) {
        continue;
      }
      _reemplazar(q.copyWith(
        state: JobState.pending,
        code: '',
        message: '',
        limpiarDependsOn: true,
        job: q.job.copyWith(createdAt: base.add(Duration(microseconds: i++))),
      ));
    }
  }

  @override
  Future<int> discardHeld(Iterable<String> jobIds) async {
    var n = 0;
    for (final id in jobIds) {
      final job = _jobs[id];
      if (job == null ||
          (job.state != JobState.blocked && job.state != JobState.waiting)) {
        continue;
      }
      _quitar(id);
      n++;
    }
    return n;
  }

  /// Orden de creación con desempate por orden de llegada. `List.sort` de Dart
  /// no es estable, así que el desempate va explícito.
  List<QueuedJob> _enOrden(List<QueuedJob> jobs) => jobs
    ..sort((a, b) {
      final c = a.job.createdAt.compareTo(b.job.createdAt);
      return c != 0 ? c : _llegada[a.id]!.compareTo(_llegada[b.id]!);
    });

  /// Saca [id] de la cola y de sus índices.
  void _quitar(String id) {
    final q = _jobs.remove(id);
    if (q == null) return;
    _cuenta[q.state] = _cuenta[q.state]! - 1;
    _llegada.remove(id);
    if (q.job.rowPk case final pk?) _porFila[(q.job.entity, pk)]?.remove(id);
  }

  @override
  Future<int> discardInvalid(Iterable<String> jobIds) async {
    var n = 0;
    for (final id in jobIds) {
      final job = _jobs[id];
      // Igual que en Drift: solo los INVALID. Un id que no existe o que está
      // en otro estado se saltea en silencio, para que descartar la cola que
      // se leyó hace un segundo no falle porque uno de esos jobs ya se movió.
      if (job == null || job.state != JobState.invalid) continue;
      _quitar(id);
      n++;
    }
    return n;
  }

  @override
  Future<SyncStatus> status() async => SyncStatus(
        pending: _cuenta[JobState.pending]!,
        inFlight: _cuenta[JobState.inFlight]!,
        invalid: _cuenta[JobState.invalid]!,
        blocked: _cuenta[JobState.blocked]!,
        waiting: _cuenta[JobState.waiting]!,
        lastPushAt: _ultimoDone,
      );

  @override
  Future<int> reclaimInFlight(Duration staleAfter) async {
    final corte = _clock().subtract(staleAfter);
    // Un `IN_FLIGHT` sin `claimedAt` es de antes de que existiera la marca:
    // se reclama, porque no hay forma de saber que alguien lo tenga y dejarlo
    // colgado para siempre es peor.
    final vencidos = [
      for (final j in withState(JobState.inFlight))
        if (j.claimedAt == null || !j.claimedAt!.isAfter(corte)) j
    ];
    for (final job in vencidos) {
      _reemplazar(
          job.copyWith(state: JobState.pending, limpiarClaimedAt: true));
    }
    return vencidos.length;
  }

  @override
  Future<List<QueuedJob>> listInvalid({int limit = 100}) async {
    final invalidos = withState(JobState.invalid).reversed.take(limit);
    return invalidos.toList();
  }

  @override
  Future<int> purgeDone(DateTime before) async {
    final aBorrar = [
      for (final j in _jobs.values)
        if (j.state == JobState.done &&
            j.doneAt != null &&
            j.doneAt!.isBefore(before))
          j.id,
    ];
    aBorrar.forEach(_quitar);
    return aBorrar.length;
  }

  void _reemplazar(QueuedJob job) {
    final anterior = _jobs[job.id]!;
    _cuenta[anterior.state] = _cuenta[anterior.state]! - 1;
    _cuenta[job.state] = _cuenta[job.state]! + 1;
    _jobs[job.id] = job;
  }

  DateTime get now => _clock();
}

/// Las tablas de negocio en memoria.
///
/// [applyDelta] es atómico de verdad: si [failOnApply] está puesto, no escribe
/// nada **ni avanza el watermark**, que es el escenario que hay que poder
/// probar sin una DB real.
class InMemoryLocalStore implements LocalStorePort {
  final Map<String, List<Map<String, Object?>>> rows = {};
  final Map<String, String> watermarks = {};

  /// Simula que la transacción local falla al aplicar el delta.
  bool failOnApply = false;

  /// Cuántas veces se aplicó un delta. Un motor que llame dos veces por página
  /// se nota acá.
  int applies = 0;

  @override
  Future<void> applyDelta(
    Map<String, List<Map<String, Object?>>> delta, {
    required String scope,
    required String? watermark,
  }) async {
    if (failOnApply) {
      throw StateError('la transacción local falló');
    }
    for (final MapEntry(key: entity, value: filas) in delta.entries) {
      (rows[entity] ??= []).addAll(filas);
    }
    if (watermark != null) watermarks[scope] = watermark;
    applies++;
  }

  @override
  Future<String?> watermarkOf(String scope) async => watermarks[scope];

  @override
  Future<void> applyVersions(String entity,
      {required String pkColumn,
      required Map<String, int> versionPorFila}) async {
    final filas = rows[entity];
    if (filas == null || versionPorFila.isEmpty) return;
    for (final (i, fila) in filas.indexed) {
      if (versionPorFila['${fila[pkColumn]}'] case final version?) {
        filas[i] = {...fila, 'sync_version': version};
      }
    }
  }
}

/// `sync_meta` en memoria (HU-SYNC-007). Un test que simula reiniciar el
/// celular arma otro motor con **el mismo** [InMemorySyncMeta], como lo haría la
/// DB en disco.
class InMemorySyncMeta implements SyncMetaPort {
  SyncMeta _meta = const SyncMeta();

  /// Cuántas veces se escribió.
  int writes = 0;

  /// Si es `true`, [write] lanza: la DB local falló.
  bool failOnWrite = false;

  @override
  Future<SyncMeta> read() async => _meta;

  @override
  Future<void> write({
    DateTime? lastPullAt,
    DateTime? lastBackupAt,
    DateTime? lastPushAt,
    SyncNetwork? lastPushNetwork,
  }) async {
    if (failOnWrite) throw StateError('la DB local falló al anotar sync_meta');
    writes++;
    final previo = _meta;
    final pushNuevo = lastPushAt != null &&
        (previo.lastPushAt == null || !lastPushAt.isBefore(previo.lastPushAt!));
    _meta = SyncMeta(
      lastPullAt: lastPullAt ?? previo.lastPullAt,
      lastBackupAt: lastBackupAt ?? previo.lastBackupAt,
      lastPushAt: pushNuevo ? lastPushAt : previo.lastPushAt,
      lastPushNetwork: pushNuevo ? lastPushNetwork : previo.lastPushNetwork,
    );
  }
}
