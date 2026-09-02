// La DB local del colportor.
//
// Tres tablas y nada más:
//
//   sync_queue   la cola de jobs (§5.1). Es del motor.
//   filas        las tablas de negocio, genéricas
//   watermarks   hasta dónde bajó cada scope
//
// **`filas` es genérica a propósito**: una tabla `(entidad, id, datos JSON)` en
// vez de 19 tablas tipadas. La sincronización no necesita el tipo —el delta
// llega como `Map<String, Object?>` y se guarda tal cual—, y una tabla por
// entidad significaría regenerar el esquema cada vez que el backend agrega una
// columna, que es exactamente el acoplamiento que el registro del servidor
// existe para evitar.
//
// Cuando haya pantallas que consulten por zona o sumen un estado de cuenta van a
// hacer falta tablas tipadas con sus índices (tarea 2.1 del plan). Esto no las
// reemplaza: las precede.

import 'package:drift/drift.dart';

part 'db.g.dart';

/// La cola de sincronización (§5.1: `PENDING` / `IN_FLIGHT` / `INVALID` / `DONE`).
@DataClassName('FilaDeCola')
class SyncQueue extends Table {
  @override
  String get tableName => 'sync_queue';

  /// Id local. Es lo que la app le pasa a `engine.requeue(jobId)`.
  TextColumn get id => text()();

  /// La idempotencia del intento (§5.3). Único: encolar dos veces el mismo
  /// intento es un bug del llamador, y acá se corta.
  TextColumn get clientOpId => text().unique()();

  TextColumn get entity => text()();
  TextColumn get op => text()();

  /// El payload tal como lo devolvió `toSyncJson()`, en JSON.
  TextColumn get payload => text()();
  IntColumn get syncVersion => integer().nullable()();

  /// El orden de subida es este, no el de inserción (§5.5).
  DateTimeColumn get createdAt => dateTime()();

  TextColumn get state => text()();
  TextColumn get code => text().withDefault(const Constant(''))();
  TextColumn get message => text().withDefault(const Constant(''))();

  /// Cuándo pasó a `DONE`, para la purga a los 7 días (§5.8).
  DateTimeColumn get doneAt => dateTime().nullable()();

  /// Cuándo un ciclo se lo llevó a `IN_FLIGHT`.
  ///
  /// Es lo que distingue "alguien lo está mandando ahora" de "quedó colgado
  /// cuando murió el proceso". Sin esto, el ciclo de segundo plano —que corre
  /// en otro isolate sobre esta misma base— reclamaría jobs que el primer
  /// plano tiene en la mano y los reenviaría en paralelo.
  DateTimeColumn get claimedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Las filas de negocio que bajaron del delta.
@DataClassName('FilaLocal')
class Filas extends Table {
  TextColumn get entidad => text()();
  TextColumn get id => text()();
  TextColumn get datos => text()();

  /// Cuándo la escribió el dispositivo. Es lo que hace posible el backup
  /// incremental (`export(since:)`): sin esto, cada backup tendría que subir la
  /// base entera y ADR-003 dejaría de cerrar en el plan de datos del colportor.
  ///
  /// Es hora local de escritura, no el `updated_at` del servidor: lo que
  /// interesa acá es qué cambió en este dispositivo desde el último backup.
  DateTimeColumn get actualizadoEn => dateTime()();

  @override
  Set<Column> get primaryKey => {entidad, id};
}

/// Hasta dónde llegó cada scope de pull.
@DataClassName('FilaWatermark')
class Watermarks extends Table {
  TextColumn get scope => text()();
  TextColumn get valor => text()();

  @override
  Set<Column> get primaryKey => {scope};
}

@DriftDatabase(tables: [SyncQueue, Filas, Watermarks])
class DbLocal extends _$DbLocal {
  DbLocal(super.e);

  /// 2: `sync_queue.claimed_at` (el lease de `IN_FLIGHT`).
  ///
  /// **Subir esto sin escribir el paso en `onUpgrade` le borra los datos a un
  /// colportor.** Drift no recrea la base sola: si el esquema no coincide,
  /// falla al abrir o —peor— queda a mitad de camino. Cada versión nueva
  /// agrega su `if (from < N)` y ninguno se saca nunca, porque un teléfono
  /// puede venir de cualquier versión anterior.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          // De 1 a 2: la marca de cuándo se tomó el job. Va nullable y sin
          // default a propósito — las filas que ya estaban en vuelo no tienen
          // un instante que se pueda inventar, y `reclaimInFlight` trata el
          // null como "vencido", que es lo correcto: dejarlas colgadas para
          // siempre sería perder esas ventas.
          if (from < 2) {
            await m.addColumn(syncQueue, syncQueue.claimedAt);
          }
        },
        onCreate: (m) async {
          await m.createAll();

          // El índice del claim: `PENDING` en orden de creación es la consulta
          // que corre en cada ciclo de sync. Sin él es un scan de la cola
          // entera, que después de una temporada no es chica.
          await customStatement(
            'create index if not exists sync_queue_claim '
            'on sync_queue (state, created_at)',
          );
          // El de la purga y el de la cola de error.
          await customStatement(
            'create index if not exists sync_queue_done '
            'on sync_queue (state, done_at)',
          );
          // El del backup incremental.
          await customStatement(
            'create index if not exists filas_actualizado '
            'on filas (actualizado_en)',
          );
        },
      );
}
