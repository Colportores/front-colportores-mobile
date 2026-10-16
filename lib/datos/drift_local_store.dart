import 'package:drift/drift.dart';
import 'package:sync_engine/sync_engine.dart';

import '../core/database/app_database.dart';
import '../core/database/fecha_utc_converter.dart';
import 'replicas_catalogo_table.dart';
import 'sync_queue_table.dart';

part 'drift_local_store.g.dart';

/// [LocalStorePort] sobre las tablas de negocio de la DB cifrada: lo que baja del servidor (el
/// delta del pull, la `server_row` de un LWW) y la `sync_version` que vuelve después de un push.
///
/// **Una sola forma de aplicar una fila del cloud a cualquier tabla.** Las columnas locales se
/// llaman como las del cloud (cada `*_table.dart` lo dice, y los modelos lo prueban con
/// `toJson()`), así que una fila se aplica columna por columna, por nombre. Solo cambia la forma de
/// dos tipos: las fechas, que el cloud manda en ISO 8601 y la DB guarda en epoch ms
/// ([FechaUtcConverter]), y lo que tiene su propio conversor (el GeoJSON de `zona`). Lo que el
/// cloud manda y la tabla local no tiene (`xmin_w`, columnas de servidor) se ignora.
///
/// Solo escribe en [entidades]: una fila del servidor no puede caer en `sync_queue`, en
/// `audit_log` ni en una tabla `local` por un nombre de entidad mal escrito.
@DriftAccessor(tables: [SyncWatermarks, SyncFueraDelArea, SyncQueue])
final class DriftLocalStore extends DatabaseAccessor<AppDatabase>
    with _$DriftLocalStoreMixin
    implements LocalStorePort {
  /// [_entidades] se pasa como `entidades:` (parámetro nombrado privado, Dart ≥ 3.10).
  DriftLocalStore(super.attachedDatabase, {required this._entidades});

  final Set<String> _entidades;

  /// Aplica el delta, los avisos de área y el watermark en una sola transacción (§10): si una
  /// fila falla, el watermark no avanza y el próximo pull vuelve a traer lo mismo.
  ///
  /// Los avisos (§2.1) viven en `sync_fuera_del_area` y nunca borran nada de las tablas de
  /// negocio. Con un `area_reset`, lo que el teléfono tenía de la entidad queda a la espera
  /// (`confirmada = false`), salvo lo que tiene escrituras en la cola sin terminar: eso el servidor
  /// todavía no lo vio, no salió de ningún lado. Lo que vuelve a bajar sale de la espera y de la
  /// marca; lo que sigue a la espera cuando llega la última página, quedó afuera.
  @override
  Future<void> applyDelta(
    Map<String, List<Map<String, Object?>>> rows, {
    required String scope,
    required String watermark,
    PullNotices notices = PullNotices.none,
  }) => transaction(() async {
    for (final entidad in notices.areaReset) {
      await _ponerALaEspera(_tabla(entidad));
    }
    for (final MapEntry(key: entidad, value: filas) in rows.entries) {
      final tabla = _tabla(entidad);
      for (final fila in filas) {
        // `<Never>`: la tabla llega como `TableInfo<Table, Object?>` y Drift verifica en runtime
        // el tipo de su fila; un insertable de `Never` es subtipo de cualquiera.
        await into(tabla).insertOnConflictUpdate(RawValuesInsertable<Never>(_valores(tabla, fila)));
      }
      final ids = [
        for (final fila in filas)
          if (fila[_pkDe(tabla)] case final id?) '$id',
      ];
      for (var i = 0; i < ids.length; i += 500) {
        final tramo = ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
        await (delete(
          syncFueraDelArea,
        )..where((f) => f.entidad.equals(entidad) & f.filaId.isIn(tramo))).go();
      }
    }
    for (final MapEntry(key: entidad, value: ids) in notices.outOfArea.entries) {
      _tabla(entidad);
      for (final id in ids) {
        await into(syncFueraDelArea).insertOnConflictUpdate(
          SyncFueraDelAreaCompanion.insert(entidad: entidad, filaId: id, confirmada: true),
        );
      }
    }
    if (notices.complete) {
      await (update(syncFueraDelArea)..where((f) => f.confirmada.equals(false))).write(
        const SyncFueraDelAreaCompanion(confirmada: Value(true)),
      );
    }

    await into(
      syncWatermarks,
    ).insertOnConflictUpdate(SyncWatermarksCompanion.insert(scope: scope, watermark: watermark));
  });

  /// Con un `area_reset` de [tabla]: todo lo que el teléfono tiene de ella pasa a esperar volver a
  /// bajar, menos lo que ya se sabe afuera y lo que tiene escrituras en la cola sin terminar.
  Future<void> _ponerALaEspera(TableInfo<Table, Object?> tabla) async {
    final pk = _pkDe(tabla);
    final entidad = tabla.actualTableName;
    await customStatement(
      'INSERT OR IGNORE INTO sync_fuera_del_area (entidad, fila_id, confirmada) '
      'SELECT ?, t."$pk", 0 FROM "$entidad" t '
      'WHERE NOT EXISTS (SELECT 1 FROM sync_queue q WHERE q.entity = ? AND q.row_pk = t."$pk" '
      "AND q.state <> 'DONE')",
      [entidad, entidad],
    );
  }

  /// La PK de [tabla] (una sola columna en toda tabla del sync).
  String _pkDe(TableInfo<Table, Object?> tabla) => tabla.$primaryKey.single.name;

  /// Los ids de [entidad] que quedaron fuera del área (§2.1): la app los marca, no los borra.
  Stream<Set<String>> observarFueraDelArea(String entidad) =>
      (select(syncFueraDelArea)
            ..where((f) => f.entidad.equals(entidad) & f.confirmada.equals(true)))
          .watch()
          .map((filas) => {for (final f in filas) f.filaId});

  @override
  Future<String?> watermarkOf(String scope) async {
    final fila = await (select(
      syncWatermarks,
    )..where((w) => w.scope.equals(scope))).getSingleOrNull();
    return fila?.watermark;
  }

  @override
  Future<void> applyVersions(
    String entity, {
    required String pkColumn,
    required Map<String, int> versionPorFila,
  }) async {
    if (versionPorFila.isEmpty) return;
    final tabla = _tabla(entity);
    final pk = _columna(tabla, pkColumn);
    final version = _columna(tabla, 'sync_version');
    await transaction(() async {
      for (final MapEntry(key: id, value: v) in versionPorFila.entries) {
        await customUpdate(
          'UPDATE "${tabla.actualTableName}" SET "${version.name}" = ? WHERE "${pk.name}" = ?',
          variables: [Variable<int>(v), Variable<String>(id)],
          updates: {tabla},
        );
      }
    });
  }

  TableInfo<Table, Object?> _tabla(String entidad) {
    if (!_entidades.contains(entidad)) {
      throw ArgumentError.value(
        entidad,
        'entidad',
        'no es una entidad sincronizable de la DB local',
      );
    }
    for (final t in attachedDatabase.allTables) {
      if (t.actualTableName == entidad) return t;
    }
    throw ArgumentError.value(entidad, 'entidad', 'no tiene tabla en la DB local');
  }

  GeneratedColumn<Object> _columna(TableInfo<Table, Object?> tabla, String nombre) {
    for (final c in tabla.$columns) {
      if (c.name == nombre) return c;
    }
    throw ArgumentError.value(nombre, 'columna', 'no existe en ${tabla.actualTableName}');
  }

  /// La fila del cloud como valores SQL de [tabla]: solo sus columnas, cada una en su tipo.
  Map<String, Expression<Object>> _valores(
    TableInfo<Table, Object?> tabla,
    Map<String, Object?> fila,
  ) => {
    for (final c in tabla.$columns)
      if (fila.containsKey(c.name)) c.name: Variable(_aSql(c, fila[c.name])),
  };

  static Object? _aSql(GeneratedColumn<Object> columna, Object? valor) {
    if (valor == null) return null;
    if (columna is GeneratedColumnWithTypeConverter) {
      final conversor = (columna as GeneratedColumnWithTypeConverter<Object?, Object>).converter;
      if (conversor is FechaUtcConverter) {
        return conversor.toSql(valor is DateTime ? valor : DateTime.parse('$valor'));
      }
      return conversor.toSql(valor);
    }
    return switch (columna.type) {
      DriftSqlType.int => (valor as num).toInt(),
      DriftSqlType.double => (valor as num).toDouble(),
      _ => valor,
    };
  }
}
