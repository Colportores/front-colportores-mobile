import 'package:drift/drift.dart';

import '../logging/app_logger.dart';

/// Base de datos local de la app: Drift sobre SQLite cifrado con SQLCipher (ADR-003, ADR-007).
///
/// Es la clase que consume el resto de la app —y el motor de sync de ADR-017 (`SyncEngine(db:
/// appDb)`, `appDb.transaction(...)`)—. **No sabe de cifrado**: recibe una conexión ya abierta con
/// la clave puesta; eso lo hace `DatabaseHelper`, que es el único que conoce el `PRAGMA key`.
///
/// Todavía **sin tablas** a propósito: el modelo de dominio es #8 y las tablas de negocio llegan
/// con cada HU (`Ventas`, `VentaItems`, … — convenciones §4.2). Este issue (#6) solo pone la
/// infraestructura para que la DB abra cifrada; agregar una tabla acá sin su HU sería modelar el
/// negocio desde infra.
///
/// Por eso extiende [GeneratedDatabase] a mano en vez de `@DriftDatabase()` + `part
/// 'app_database.g.dart'`: sin tablas, esto es exactamente lo que `drift_dev` generaría, y
/// `drift_dev` todavía no se puede agregar al proyecto (conflicto de analyzer con `custom_lint`,
/// ver la nota en `pubspec.yaml`). Cuando entre la primera tabla (#8), se resuelve ese tooling y
/// esta clase pasa a `@DriftDatabase(tables: [...]) class AppDatabase extends _$AppDatabase`,
/// [schemaVersion] sube y la migración se escribe en [migration].
///
/// [migration] es la estrategia por defecto de Drift (crear todo al crear la DB). Cualquier
/// política más elaborada (migraciones paso a paso, `foreign_keys`, WAL) se decide con #8, no acá.
/// Lo único que agrega es el log `[DB][MIGRATION]` de convenciones §7.4.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.e, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  /// Sin tablas hasta #8 (ver doc de la clase).
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  /// Versión del esquema (`PRAGMA user_version`). HU-AUTH-009 la lee para validar que la DB abrió
  /// bien; `DatabaseHelper.abrir` hace esa comprobación.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (detalles) async {
      if (detalles.wasCreated) {
        _log.info(LogModulo.db, 'DB_CREADA', 'esquema inicial creado', {'version': schemaVersion});
      } else if (detalles.hadUpgrade) {
        _log.info(LogModulo.db, 'MIGRATION', 'migración ejecutada', {
          'from': detalles.versionBefore,
          'to': detalles.versionNow,
        });
      }
    },
  );
}
