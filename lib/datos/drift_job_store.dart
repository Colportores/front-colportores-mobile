// `JobStorePort` sobre la DB local: la cola de jobs del motor, persistida y cifrada.
//
// Hasta acá el motor corre sobre `InMemoryJobStore`, o sea que al cerrar la app se pierde todo lo
// que estaba esperando subir. Una venta cargada sin señal, la app cerrada antes de recuperar
// conexión, y esa venta no existió nunca. Eso es lo que este archivo arregla.
//
// El motor se verificó entero contra el fake, así que lo único que garantiza que esto se comporte
// igual es `runJobStoreContract` —la definición ejecutable del puerto—, que corre en
// `test/unit/datos/drift_job_store_test.dart`.
//
// Está escrito con `customSelect`/`customUpdate` en vez de la API tipada de Drift porque la tabla
// todavía no puede ser una `Table` generada: ver la cabecera de `esquema_sync.dart`.

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sync_engine/sync_engine.dart';

import 'esquema_sync.dart';

class DriftJobStore implements JobStorePort {
  DriftJobStore(this._db, {UuidV7? uuid, DateTime Function()? clock})
    : _uuid = uuid ?? UuidV7(),
      _clock = clock ?? (() => DateTime.now().toUtc());

  final DatabaseConnectionUser _db;
  final UuidV7 _uuid;
  final DateTime Function() _clock;

  /// La cola se crea la primera vez que se la usa, no al abrir la DB.
  ///
  /// Así el store se construye con una conexión y nada más —que es lo que necesita el contrato del
  /// puerto, y lo que hace que el motor no dependa del orden de arranque de la app—. Si el DDL
  /// falla, el future fallado no queda cacheado: el próximo intento lo vuelve a probar en vez de
  /// dejar la cola rota hasta que alguien reinicie.
  Future<void>? _creada;

  Future<void> _asegurarTabla() {
    return _creada ??= crearSyncQueue(_db).catchError((Object e) {
      _creada = null;
      throw e;
    });
  }

  @override
  Future<String> append(SyncJob job) async {
    await _asegurarTabla();
    final id = _uuid.next();
    await _db.customInsert(
      'insert into sync_queue '
      '(id, client_op_id, entity, op, payload, sync_version, created_at, state) '
      'values (?, ?, ?, ?, ?, ?, ?, ?)',
      variables: [
        Variable<String>(id),
        Variable<String>(job.clientOpId),
        Variable<String>(job.entity),
        Variable<String>(job.op.name),
        Variable<String>(jsonEncode(job.payload)),
        Variable<int>(job.syncVersion),
        Variable<int>(_enSegundos(job.createdAt)),
        const Variable<String>(estadoPending),
      ],
    );
    return id;
  }

  @override
  Future<List<QueuedJob>> claimPending({int limit = 100}) async {
    await _asegurarTabla();
    // Seleccionar y marcar tienen que ser indivisibles: si dos ciclos se cruzan entre el SELECT y
    // el UPDATE, los dos se llevan el mismo job y la misma venta sale dos veces. El `client_op_id`
    // la deduplica del lado del servidor (§5.3), pero gastando el viaje que RR-07 cuida.
    return _db.transaction(() async {
      final filas = await _db
          .customSelect(
            // §5.5: orden de creación, no de inserción. El desempate por `id` es lo
            // que hace la salida determinista cuando dos jobs comparten el instante:
            // sin él, un update podría adelantarse al insert de su propia fila.
            'select * from sync_queue where state = ? order by created_at, id limit ?',
            variables: [const Variable<String>(estadoPending), Variable<int>(limit)],
          )
          .get();
      if (filas.isEmpty) return const <QueuedJob>[];

      final ids = [for (final f in filas) f.read<String>('id')];
      final ahora = _clock();
      await _db.customUpdate(
        'update sync_queue set state = ?, claimed_at = ? '
        'where id in (${_marcadores(ids.length)})',
        variables: [
          const Variable<String>(estadoInFlight),
          Variable<int>(_enSegundos(ahora)),
          for (final id in ids) Variable<String>(id),
        ],
        updateKind: UpdateKind.update,
      );

      return [for (final f in filas) _aQueuedJob(f, estado: JobState.inFlight, claimedAt: ahora)];
    });
  }

  @override
  Future<void> markDone(Iterable<String> jobIds, {required DateTime at}) async {
    final ids = jobIds.toList();
    if (ids.isEmpty) return;
    await _asegurarTabla();
    await _db.customUpdate(
      'update sync_queue set state = ?, done_at = ? '
      'where id in (${_marcadores(ids.length)})',
      variables: [
        const Variable<String>(estadoDone),
        Variable<int>(_enSegundos(at)),
        for (final id in ids) Variable<String>(id),
      ],
      updateKind: UpdateKind.update,
    );
  }

  @override
  Future<void> markInvalid(String jobId, {required String code, String message = ''}) async {
    await _asegurarTabla();
    // Sin condición sobre el estado: el motor también manda a la cola de error un job que nunca
    // llegó a viajar —un payload que no pasa la validación local—, y ese todavía está en PENDING.
    await _db.customUpdate(
      'update sync_queue set state = ?, code = ?, message = ? where id = ?',
      variables: [
        const Variable<String>(estadoInvalid),
        Variable<String>(code),
        Variable<String>(message),
        Variable<String>(jobId),
      ],
      updateKind: UpdateKind.update,
    );
  }

  @override
  Future<void> markPending(Iterable<String> jobIds) async {
    final ids = jobIds.toList();
    if (ids.isEmpty) return;
    await _asegurarTabla();
    await _db.customUpdate(
      // El claim se limpia al soltar el job: si quedara pegado, el próximo reclamo lo mediría
      // contra un instante que ya no significa nada.
      'update sync_queue set state = ?, claimed_at = null '
      'where id in (${_marcadores(ids.length)})',
      variables: [
        const Variable<String>(estadoPending),
        for (final id in ids) Variable<String>(id),
      ],
      updateKind: UpdateKind.update,
    );
  }

  @override
  Future<void> requeue(String jobId) async {
    await _asegurarTabla();
    // El código y el mensaje se limpian: el error viejo no puede quedar pegado a un job que el
    // colportor ya corrigió, o la cola de error muestra para siempre un motivo que dejó de ser
    // cierto.
    await _db.customUpdate(
      "update sync_queue set state = ?, code = '', message = '' where id = ?",
      variables: [const Variable<String>(estadoPending), Variable<String>(jobId)],
      updateKind: UpdateKind.update,
    );
  }

  @override
  Future<int> discardInvalid(Iterable<String> jobIds) async {
    final ids = jobIds.toList();
    if (ids.isEmpty) return 0;
    await _asegurarTabla();
    // El `state = INVALID` del where no es decorativo: es lo que hace que borrar sea seguro contra
    // el isolate de segundo plano (RF-SY07). Los dos motores comparten esta base, y sin esa
    // condición un descarte disparado desde la pantalla podría llevarse un job que el ciclo de
    // fondo acaba de pasar a IN_FLIGHT y está mandando en ese momento.
    return _db.customUpdate(
      'delete from sync_queue '
      'where state = ? and id in (${_marcadores(ids.length)})',
      variables: [
        const Variable<String>(estadoInvalid),
        for (final id in ids) Variable<String>(id),
      ],
      updateKind: UpdateKind.delete,
    );
  }

  @override
  Future<int> reclaimInFlight(Duration staleAfter) async {
    await _asegurarTabla();
    // Un job queda IN_FLIGHT mientras un ciclo lo tiene en la mano. Si el proceso muere ahí
    // —Android matando la app, batería—, nadie lo reclama: `claimPending` no lo mira y la venta no
    // sube nunca. Reenviarlo es seguro: el `client_op_id` hace que el servidor conteste
    // `duplicate` (§5.3).
    //
    // Pero solo lo **vencido**: el ciclo de segundo plano corre en otro isolate sobre esta misma
    // base, y un reclamo incondicional se llevaría puestos los jobs que el primer plano está
    // mandando en ese instante.
    final corte = _enSegundos(_clock().subtract(staleAfter));
    return _db.customUpdate(
      'update sync_queue set state = ?, claimed_at = null '
      // `claimed_at` nulo es una fila escrita antes de que existiera la marca: no hay instante
      // contra el cual medirla, y dejarla colgada para siempre sería perder esa venta.
      'where state = ? and (claimed_at is null or claimed_at <= ?)',
      variables: [
        const Variable<String>(estadoPending),
        const Variable<String>(estadoInFlight),
        Variable<int>(corte),
      ],
      updateKind: UpdateKind.update,
    );
  }

  @override
  Future<SyncStatus> status() async {
    await _asegurarTabla();
    final filas = await _db
        .customSelect('select state, count(*) as n from sync_queue group by state')
        .get();
    final porEstado = {for (final f in filas) f.read<String>('state'): f.read<int>('n')};
    return SyncStatus(
      pending: porEstado[estadoPending] ?? 0,
      inFlight: porEstado[estadoInFlight] ?? 0,
      invalid: porEstado[estadoInvalid] ?? 0,
    );
  }

  @override
  Future<List<QueuedJob>> listInvalid({int limit = 100}) async {
    await _asegurarTabla();
    final filas = await _db
        .customSelect(
          // Del más reciente al más viejo: lo que el colportor acaba de romper es lo
          // que necesita ver primero.
          'select * from sync_queue where state = ? order by created_at desc, id desc limit ?',
          variables: [const Variable<String>(estadoInvalid), Variable<int>(limit)],
        )
        .get();
    return [for (final f in filas) _aQueuedJob(f, estado: JobState.invalid)];
  }

  @override
  Future<int> purgeDone(DateTime before) async {
    await _asegurarTabla();
    return _db.customUpdate(
      'delete from sync_queue where state = ? and done_at < ?',
      variables: [const Variable<String>(estadoDone), Variable<int>(_enSegundos(before))],
      updateKind: UpdateKind.delete,
    );
  }

  QueuedJob _aQueuedJob(QueryRow f, {required JobState estado, DateTime? claimedAt}) => QueuedJob(
    id: f.read<String>('id'),
    state: estado,
    code: f.read<String>('code'),
    message: f.read<String>('message'),
    doneAt: _desdeSegundos(f.readNullable<int>('done_at')),
    claimedAt: claimedAt ?? _desdeSegundos(f.readNullable<int>('claimed_at')),
    job: SyncJob(
      clientOpId: f.read<String>('client_op_id'),
      entity: f.read<String>('entity'),
      op: Op.values.byName(f.read<String>('op')),
      payload: (jsonDecode(f.read<String>('payload')) as Map).cast<String, Object?>(),
      syncVersion: f.readNullable<int>('sync_version'),
      createdAt: _desdeSegundos(f.read<int>('created_at'))!,
    ),
  );
}

/// `?, ?, ?` para un `in (...)` de [n] elementos.
///
/// Interpolar los ids en el SQL sería más corto y sería una inyección: el `client_op_id` y la
/// entidad salen de datos que la app escribe, no de una lista blanca.
String _marcadores(int n) => List.filled(n, '?').join(', ');

/// Las fechas van en segundos unix porque es como Drift guarda un `DateTimeColumn` por defecto:
/// el día que la tabla pase a ser una `Table` generada (#8), las filas ya escritas se leen sin
/// convertir nada. Ver `esquema_sync.dart`.
int _enSegundos(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000;

DateTime? _desdeSegundos(int? segundos) =>
    segundos == null ? null : DateTime.fromMillisecondsSinceEpoch(segundos * 1000, isUtc: true);
