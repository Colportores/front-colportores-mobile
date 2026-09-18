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
    _cuenta[JobState.pending] = _cuenta[JobState.pending]! + 1;
    return id;
  }

  @override
  Future<List<QueuedJob>> claimPending({int limit = 500}) async {
    final tomados = <QueuedJob>[];
    // §5.5: orden de creación. La lista ya está en ese orden porque append
    // agrega al final; ordenar explícito deja el invariante escrito.
    final candidatos = [
      ..._jobs.values.where((j) => j.state == JobState.pending)
    ]..sort((a, b) => a.job.createdAt.compareTo(b.job.createdAt));

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
  Future<int> discardInvalid(Iterable<String> jobIds) async {
    var n = 0;
    for (final id in jobIds) {
      final job = _jobs[id];
      // Igual que en Drift: solo los INVALID. Un id que no existe o que está
      // en otro estado se saltea en silencio, para que descartar la cola que
      // se leyó hace un segundo no falle porque uno de esos jobs ya se movió.
      if (job == null || job.state != JobState.invalid) continue;
      _cuenta[JobState.invalid] = _cuenta[JobState.invalid]! - 1;
      _jobs.remove(id);
      n++;
    }
    return n;
  }

  @override
  Future<SyncStatus> status() async => SyncStatus(
        pending: _cuenta[JobState.pending]!,
        inFlight: _cuenta[JobState.inFlight]!,
        invalid: _cuenta[JobState.invalid]!,
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
    for (final id in aBorrar) {
      _cuenta[JobState.done] = _cuenta[JobState.done]! - 1;
      _jobs.remove(id);
    }
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
    required String watermark,
  }) async {
    if (failOnApply) {
      throw StateError('la transacción local falló');
    }
    for (final MapEntry(key: entity, value: filas) in delta.entries) {
      (rows[entity] ??= []).addAll(filas);
    }
    watermarks[scope] = watermark;
    applies++;
  }

  @override
  Future<String?> watermarkOf(String scope) async => watermarks[scope];
}
