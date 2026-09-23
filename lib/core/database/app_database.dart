import 'package:drift/drift.dart';

import '../../features/jornada/data/datasources/jornadas_table.dart';
import '../logging/app_logger.dart';
import 'fecha_utc_converter.dart';

part 'app_database.g.dart';

/// Base de datos local de la app: Drift sobre SQLite cifrado con SQLCipher (ADR-003, ADR-007).
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
@DriftDatabase(tables: [Jornadas])
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
  static const int versionEsquema = 2;

  /// Versión del esquema (`PRAGMA user_version`). HU-AUTH-009 la lee para validar que la DB abrió
  /// bien; `DatabaseHelper.abrir` hace esa comprobación.
  @override
  int get schemaVersion => versionEsquema;

  /// Una DB nueva se crea entera con el esquema actual ([Migrator.createAll]). Una existente sube
  /// paso a paso desde su versión: cada `if (desde < N)` la lleva de `N - 1` a `N`, y un paso ya
  /// publicado no se edita.
  ///
  /// Ojo con el primer paso que **modifique** una tabla existente: `createTable(jornadas)` crea
  /// `jornada` con su definición *actual*, así que si la versión 3 le agrega una columna, un
  /// dispositivo que venga de la 1 ya la tendría al llegar al paso `2 → 3` y el `addColumn`
  /// fallaría. En ese momento hay que congelar cada versión con `drift_dev make-migrations`
  /// (`stepByStep`).
  ///
  /// TODO(#70): el test de migración no alcanza todavía para la versión 3. Arranca solo desde la
  /// 1 y compara el texto de `sqlite_master`, así que no detecta un paso `N → N+1` olvidado
  /// (desde la 1, `createTable` ya deja el esquema actual) y daría un falso fallo después de un
  /// `ALTER TABLE … ADD COLUMN` (SQLite guarda otro texto que el de un `CREATE TABLE` nuevo). Lo
  /// que corresponde —congelar la v2 con `make-migrations`, testear también desde la 2 y comparar
  /// con el `SchemaVerifier` de Drift— hoy no compila: `drift_dev` 2.34.0 no anda con el `drift`
  /// del lock, y los `drift_dev` que sí andan piden analyzer 13, que `riverpod_generator` no
  /// deja. Hay que resolverlo antes de la versión 3 (detalle en #70).
  ///
  /// `beforeOpen` agrega el log `[DB][MIGRATION]` de convenciones §7.4.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, desde, hasta) async {
      if (desde < 2) {
        await m.createTable(jornadas);
        await m.createIndex(jornadaColportorIdx);
      }
    },
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
