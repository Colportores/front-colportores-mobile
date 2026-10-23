import 'package:drift/drift.dart';
import 'package:sync_engine/sync_engine.dart';

import '../core/database/app_database.dart';
import '../core/database/fecha_utc_converter.dart';
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
@DriftAccessor(tables: [SyncWatermarks])
final class DriftLocalStore extends DatabaseAccessor<AppDatabase>
    with _$DriftLocalStoreMixin
    implements LocalStorePort {
  /// [_entidades] se pasa como `entidades:` (parámetro nombrado privado, Dart ≥ 3.10).
  DriftLocalStore(super.attachedDatabase, {required this._entidades});

  final Set<String> _entidades;

  /// Aplica el delta y el watermark en una sola transacción (§10): si una fila falla, el
  /// watermark no avanza y el próximo pull vuelve a traer lo mismo.
  @override
  Future<void> applyDelta(
    Map<String, List<Map<String, Object?>>> rows, {
    required String scope,
    required String? watermark,
  }) => transaction(() async {
    for (final MapEntry(key: entidad, value: filas) in rows.entries) {
      final tabla = _tabla(entidad);
      for (final fila in filas) {
        // `<Never>`: la tabla llega como `TableInfo<Table, Object?>` y Drift verifica en runtime
        // el tipo de su fila; un insertable de `Never` es subtipo de cualquiera.
        await into(tabla).insertOnConflictUpdate(RawValuesInsertable<Never>(_valores(tabla, fila)));
      }
    }
    // Sin watermark (la `server_row` de un LWW) se deja el que había.
    if (watermark != null) {
      await into(
        syncWatermarks,
      ).insertOnConflictUpdate(SyncWatermarksCompanion.insert(scope: scope, watermark: watermark));
    }
  });

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
      // Las fechas del cloud llegan como texto ISO. Una columna `nullable()` envuelve el conversor
      // en un `NullAwareTypeConverter`, que ya no es un `FechaUtcConverter` pero sigue siendo un
      // `TypeConverter<DateTime?, int?>`: se las reconoce por eso, con o sin `null`.
      if (conversor is TypeConverter<DateTime?, int?>) {
        return conversor.toSql(valor is DateTime ? valor : DateTime.parse('$valor'));
      }
      return conversor.toSql(valor);
    }
    return switch (columna.type) {
      DriftSqlType.int => (valor as num).toInt(),
      DriftSqlType.double => (valor as num).toDouble(),
      // El cloud manda `true`/`false` (`agenda.es_estricta`); Drift lo guarda como 0 o 1 al
      // atar la variable, pero su validación espera un `bool`, no el entero.
      DriftSqlType.bool => valor is num ? valor != 0 : valor,
      _ => valor,
    };
  }
}
