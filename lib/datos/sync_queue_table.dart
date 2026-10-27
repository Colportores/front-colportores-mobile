import 'package:drift/drift.dart';

import '../core/database/fecha_utc_converter.dart';

/// Los estados de `sync_queue` (contrato §5.1 y §2.2), tal como viajan a la columna `state`.
///
/// Son texto y no un entero a propósito: la cola se inspecciona a mano cuando algo raro pasa en
/// campo, y `'IN_FLIGHT'` se lee en un dump de sqlite sin buscar la tabla de códigos.
abstract final class EstadoJob {
  static const pending = 'PENDING';
  static const inFlight = 'IN_FLIGHT';
  static const invalid = 'INVALID';
  static const done = 'DONE';
  static const blocked = 'BLOCKED';
  static const waiting = 'WAITING';

  /// Lo que todavía no salió: lo que se puede fundir o reemplazar (`unsentFor`, `replacePayload`).
  static const sinMandar = [pending, blocked, waiting];

  /// Lo que el servidor todavía no aplicó: lo que recibe la versión nueva (`rebaseVersions`).
  static const sinAplicar = [pending, inFlight, blocked, waiting];
}

/// `sync_queue`: la cola de jobs del motor de sync (contrato §5.1), en la DB cifrada.
///
/// **Solo local e infraestructura**: no es una entidad del contrato (§2), no se registra en el
/// `SpecRegistry` y no sube. Viaja en el backup E2E con el resto de la DB (§7 fase 1): los jobs
/// encolados al momento del backup tienen que volver a existir, o se pierden las ventas que
/// esperaban subir.
///
/// [createdAt] es el orden de la cola (§5.5) y [id] (UUID v7 del motor, monótono) desempata los
/// del mismo milisegundo, así que el orden de llegada se conserva. `release` mueve [createdAt] al
/// final de la cola: por eso no es la fecha de la escritura, sino su lugar en la fila.
@DataClassName('SyncQueueFila')
@TableIndex(name: 'sync_queue_estado_orden', columns: {#state, #createdAt, #id})
@TableIndex(name: 'sync_queue_fila', columns: {#entity, #rowPk})
@TableIndex(name: 'sync_queue_done_at', columns: {#state, #doneAt})
class SyncQueue extends Table {
  @override
  String get tableName => 'sync_queue';

  TextColumn get id => text()();

  /// El `client_op_id` (§5.3): lo que deduplica el servidor.
  TextColumn get clientOpId => text().unique()();

  /// Nombre remoto de la entidad.
  TextColumn get entity => text()();

  /// `insert`, `update` o `delete` (el `Op` del motor).
  TextColumn get op => text()();

  /// La fila en JSON, con los nombres de columna del cloud.
  TextColumn get payload => text()();

  /// La versión esperada (§5.4). `null` en un alta.
  IntColumn get syncVersion => integer().nullable()();

  /// La PK de la fila que escribe (`SyncJob.rowPk`), para encontrar sus escrituras por índice.
  TextColumn get rowPk => text().nullable()();

  IntColumn get createdAt => integer().map(const FechaUtcConverter())();

  /// Ver [EstadoJob].
  TextColumn get state => text()();

  /// Por qué quedó `INVALID`, `BLOCKED` o `WAITING`: lo que la app le muestra al colportor.
  TextColumn get code => text().withDefault(const Constant(''))();

  TextColumn get message => text().withDefault(const Constant(''))();

  /// En `WAITING`: la PK de la fila que el servidor no tiene y que este job nombra (§2.2).
  TextColumn get dependsOn => text().nullable()();

  IntColumn get doneAt => integer().nullable().map(const FechaUtcConverter())();

  /// Cuándo un ciclo se lo llevó a `IN_FLIGHT`: separa «viajando» de «colgado».
  IntColumn get claimedAt => integer().nullable().map(const FechaUtcConverter())();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    "CHECK (op IN ('insert', 'update', 'delete'))",
    "CHECK (state IN ('PENDING', 'IN_FLIGHT', 'INVALID', 'DONE', 'BLOCKED', 'WAITING'))",
  ];
}

/// `sync_watermark`: hasta dónde se bajó cada alcance del pull (contrato §10). El motor lo trata
/// como opaco. Se escribe en la misma transacción que el delta que lo trajo (`applyDelta`).
@DataClassName('SyncWatermarkFila')
class SyncWatermarks extends Table {
  @override
  String get tableName => 'sync_watermark';

  TextColumn get scope => text()();

  TextColumn get watermark => text()();

  @override
  Set<Column<Object>> get primaryKey => {scope};
}

/// `sync_meta`: lo que el motor se acuerda entre una apertura de la app y la siguiente (HU-SYNC-007,
/// #486): cuándo bajó el delta por última vez, cuándo hizo el último respaldo y por qué red salió el
/// último envío. Es lo que muestra la vista de estado de sync después de reiniciar el celular.
///
/// **Aparte de [SyncWatermarks] a propósito**: un watermark es un cursor del pull que se le manda al
/// servidor; esto es información para la pantalla y no sale del teléfono. Una fila por dato
/// (`last_pull_at`, `last_backup_at`, `last_push_at`, `last_push_network`), con la fecha en ISO 8601
/// UTC y la red por su nombre (`wifi` o `mobile`): se lee a ojo en un dump de sqlite. Solo local e
/// infraestructura: no es una entidad del contrato, no se registra en el `SpecRegistry` y no sube.
@DataClassName('SyncMetaFila')
class SyncMetas extends Table {
  @override
  String get tableName => 'sync_meta';

  TextColumn get clave => text()();

  TextColumn get valor => text()();

  @override
  Set<Column<Object>> get primaryKey => {clave};
}
