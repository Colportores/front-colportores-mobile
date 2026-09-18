// La `sync_queue` del motor (contrato §5.1), en SQL crudo sobre la conexión que ya abrió cifrada.
//
// **Por qué SQL crudo y no una tabla Drift.** `drift_dev` todavía no está en el proyecto (ver la
// nota del `pubspec.yaml`: la línea de `drift` que empaqueta SQLCipher exige analyzer ≥ 10 y
// `custom_lint` 0.8.1 quedó en ^8), y `AppDatabase` declara `allTables => const []` a propósito
// hasta que entre el modelo de dominio (#8). Esta tabla no es del dominio: es infraestructura del
// motor (ADR-017, y `/lib/datos/` en CODEOWNERS). No tiene por qué esperar a #8 ni por qué obligar
// a resolver el tooling antes de tiempo.
//
// **Qué pasa cuando #8 resuelva el codegen.** Esto se reemplaza por una `class SyncQueue extends
// Table` registrada en `allTables`, y este DDL se vuelve el paso 1 del `onUpgrade`. El esquema de
// acá es exactamente el que genera esa tabla: mismos nombres en snake_case, y las fechas en
// segundos unix, que es como Drift guarda un `DateTimeColumn` por defecto. Por eso la adopción es
// un `CREATE TABLE IF NOT EXISTS` que no encuentra nada que hacer, y no una migración de datos.
//
// **Lo que este archivo no toca**: `schemaVersion` ni `allTables` de `AppDatabase`. La versión del
// esquema sigue siendo la del dominio; la cola es del motor y se crea sola la primera vez que se
// la usa.

import 'package:drift/drift.dart';

/// Los cuatro estados del §5.1, tal como viajan a la columna `state`.
///
/// Son texto y no un entero a propósito: la cola se inspecciona a mano cuando algo raro pasa en
/// campo, y `'IN_FLIGHT'` se lee en un dump de sqlite sin tener que buscar la tabla de códigos.
const String estadoPending = 'PENDING';
const String estadoInFlight = 'IN_FLIGHT';
const String estadoInvalid = 'INVALID';
const String estadoDone = 'DONE';

const String _tabla = '''
create table if not exists sync_queue (
  id           text    not null primary key,
  client_op_id text    not null unique,
  entity       text    not null,
  op           text    not null,
  payload      text    not null,
  sync_version integer,
  created_at   integer not null,
  state        text    not null,
  code         text    not null default '',
  message      text    not null default '',
  done_at      integer,
  claimed_at   integer
)
''';

/// El índice del ciclo: `where state = ? order by created_at, id limit ?`.
///
/// Las tres columnas en ese orden hacen que el claim sea una lectura del índice y nada más. Sin
/// él, cada ciclo ordena la cola entera: con una jornada sin señal eso son miles de filas, en un
/// teléfono de gama baja, justo cuando vuelve la conexión y hay que subir rápido.
const String _indicePendientes =
    'create index if not exists sync_queue_estado_orden on sync_queue (state, created_at, id)';

/// La purga de §5.8 (`state = 'DONE' and done_at < ?`) y el reclamo de los `IN_FLIGHT` vencidos
/// filtran por una fecha distinta de `created_at`, así que no les sirve el índice de arriba.
const String _indicePurga =
    'create index if not exists sync_queue_done_at on sync_queue (state, done_at)';

/// Crea la cola si no existe. Es idempotente y barata: correrla en cada arranque no cuesta nada.
Future<void> crearSyncQueue(DatabaseConnectionUser db) async {
  await db.customStatement(_tabla);
  await db.customStatement(_indicePendientes);
  await db.customStatement(_indicePurga);
}
