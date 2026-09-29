import 'package:drift/drift.dart';

import '../../features/jornada/data/datasources/jornadas_table.dart';
import '../../features/mapa/data/datasources/espacios_table.dart';
import '../../features/mapa/data/datasources/ubicaciones_table.dart';
import '../logging/app_logger.dart';
import 'app_database.steps.dart';
import 'fecha_utc_converter.dart';

part 'app_database.g.dart';

/// Base de datos local de la app: Drift sobre SQLite cifrado con SQLCipher (ADR-006, ADR-009).
///
/// Es la clase que consume el resto de la app —y el motor de sync de ADR-017 (`SyncEngine(db:
/// appDb)`, `appDb.transaction(...)`)—. **No sabe de cifrado**: recibe una conexión ya abierta con
/// la clave puesta; eso lo hace `DatabaseHelper`, que es el único que conoce el `PRAGMA key`.
///
/// Las tablas de negocio llegan con cada HU (convenciones §4.2) y viven en su feature
/// (`features/<feature>/data/datasources/<tabla>_table.dart`); acá solo se registran en
/// `@DriftDatabase(tables: [...])`. `drift_dev` genera `_$AppDatabase` en `app_database.g.dart`,
/// que no se versiona: lo regenera `build_runner`, también en CI. Agregar una tabla es siempre lo
/// mismo: sumarla a la lista, subir [versionEsquema] y escribir su paso en [migration], con test.
///
/// Las fechas de toda tabla van en epoch ms UTC con [FechaUtcConverter]
/// (08-conceptos-transversales §8.11), no con columnas `dateTime()` de Drift.
@DriftDatabase(tables: [Jornadas, Ubicaciones, Espacios])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final AppLogger _log;

  /// Versión del esquema (`PRAGMA user_version`). Constante además de getter porque
  /// `DatabaseHelper` la necesita **antes** de construir la DB: el `setup` de la conexión rechaza
  /// un archivo de una versión posterior antes de que Drift lo migre.
  ///
  /// Historia (forward-only, 08-conceptos-transversales §8.10):
  /// - 1: sin tablas (#6).
  /// - 2: `jornada` (#70).
  /// - 3: `ubicacion` y `espacio` (#192).
  ///
  /// Al subirla: `dart run drift_dev make-migrations` congela la versión nueva en `drift_schemas/`,
  /// regenera `app_database.steps.dart` y los tests de `test/drift/` (convenciones §9).
  static const int versionEsquema = 3;

  /// Versión del esquema (`PRAGMA user_version`). HU-AUTH-009 la lee para validar que la DB abrió
  /// bien; `DatabaseHelper.abrir` hace esa comprobación.
  @override
  int get schemaVersion => versionEsquema;

  /// Una DB nueva se crea entera con el esquema actual ([Migrator.createAll]). Una existente sube
  /// paso a paso desde su versión con [stepByStep] (`app_database.steps.dart`, generado por
  /// `drift_dev make-migrations`): cada paso `fromNToM` recibe el esquema **congelado** de la
  /// versión `M` (`drift_schemas/`), así que crear una tabla en el paso 1 → 2 la crea como era en
  /// la 2 aunque después cambie. Un paso ya publicado no se edita. Los tests de
  /// `test/drift/app_database/` migran desde cada versión congelada y comparan con
  /// `SchemaVerifier` (convenciones §9).
  ///
  /// **Toda la subida va en una transacción, con `user_version` adentro.** Drift 2.34 corre
  /// `onUpgrade` sin transacción y escribe la versión recién al final, y `createIndex` no usa
  /// `IF NOT EXISTS`: un corte a mitad de camino (disco lleno, la app matada) dejaría las tablas
  /// del paso a medias con la versión vieja, y cada apertura siguiente fallaría en el mismo
  /// `CREATE INDEX` —la DB quedaría inabrible y solo quedaría "Empezar de nuevo", con las jornadas
  /// sin sincronizar adentro—. En SQLite el DDL es transaccional: si algo falla se revierte todo y
  /// la próxima apertura reintenta desde la versión de antes.
  ///
  /// `beforeOpen` agrega el log `[DB][MIGRATION]` de convenciones §7.4.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, desde, hasta) => transaction(() async {
      await _pasos(m, desde, hasta);
      await customStatement('PRAGMA user_version = $hasta');
    }),
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

  /// Los pasos `N → N+1` contra el esquema congelado de cada versión (`app_database.steps.dart`).
  static final OnUpgrade _pasos = stepByStep(
    from1To2: (m, esquema) async {
      await m.createTable(esquema.jornada);
      await m.createIndex(esquema.jornadaColportorIdx);
    },
    from2To3: (m, esquema) async {
      await m.createTable(esquema.ubicacion);
      await m.createIndex(esquema.ubicacionCiudadIdx);
      await m.createTable(esquema.espacio);
      await m.createIndex(esquema.espacioUbicacionIdx);
    },
  );
}
