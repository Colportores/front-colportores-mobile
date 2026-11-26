import 'package:drift/drift.dart';
import 'package:sync_engine/sync_engine.dart';

import '../core/database/app_database.dart';
import '../core/database/fecha_utc_converter.dart';
import 'sync_fuera_del_area_table.dart';
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
  /// [_entidades] se pasa como `entidades:` y [_despuesDeAplicar] como `despuesDeAplicar:`
  /// (parámetros nombrados privados, Dart ≥ 3.10).
  DriftLocalStore(super.attachedDatabase, {required this._entidades, this._despuesDeAplicar});

  final Set<String> _entidades;

  /// Lo que la app hace con lo que bajó, **después** de que la transacción del delta se confirmó (por
  /// ejemplo, volver a calcular lo que depende de las filas nuevas). Recibe las filas del delta, tal
  /// como las entregó el servidor. Corre fuera de la transacción: si falla, el delta ya está aplicado
  /// y el watermark avanzó, así que quien lo pasa se ocupa de no lanzar (un fallo acá no puede dejar
  /// al pull trabado). `null` en el teléfono que no lo necesita (la recuperación de un respaldo).
  final Future<void> Function(Map<String, List<Map<String, Object?>>> filas)? _despuesDeAplicar;

  /// Aplica el delta, los avisos de área y el watermark en una sola transacción (§10): si una
  /// fila falla, el watermark no avanza y el próximo pull vuelve a traer lo mismo.
  ///
  /// Los avisos (§2.1) viven en `sync_fuera_del_area` y nunca borran nada de las tablas de
  /// negocio. Con un `area_reset`, lo que el teléfono tenía de la entidad queda a la espera
  /// (`confirmada = false`), salvo lo que tiene escrituras en la cola sin terminar: eso el servidor
  /// todavía no lo vio, no salió de ningún lado. Lo que vuelve a bajar sale de la espera y de la
  /// marca; lo que sigue a la espera cuando llega la última página, quedó afuera.
  ///
  /// [unapplied] se pregunta acá adentro, en la transacción: el `DriftJobStore` del motor usa esta
  /// misma DB, así que su consulta corre en ella, y la escritura de la app (fila y job en otra
  /// transacción) queda entera antes o entera después del delta (#714).
  @override
  Future<void> applyDelta(
    Map<String, List<Map<String, Object?>>> rows, {
    required String scope,
    required String? watermark,
    PullNotices notices = PullNotices.none,
    UnappliedRows? unapplied,
  }) async {
    await _aplicar(
      rows,
      scope: scope,
      watermark: watermark,
      notices: notices,
      unapplied: unapplied,
    );
    if (rows.values.any((filas) => filas.isNotEmpty)) await _despuesDeAplicar?.call(rows);
  }

  Future<void> _aplicar(
    Map<String, List<Map<String, Object?>>> rows, {
    required String scope,
    required String? watermark,
    required PullNotices notices,
    required UnappliedRows? unapplied,
  }) => transaction(() async {
    for (final entidad in notices.areaReset) {
      await _ponerALaEspera(_tabla(entidad), unapplied);
    }
    for (final MapEntry(key: entidad, value: todas) in rows.entries) {
      final tabla = _tabla(entidad);
      final pk = _pkDe(tabla);
      final ocupadas = unapplied == null || todas.isEmpty
          ? const <String>{}
          : await unapplied(entidad, [
              for (final fila in todas)
                if (fila[pk] case final id?) '$id',
            ]);
      final filas = ocupadas.isEmpty
          ? todas
          : [
              for (final fila in todas)
                if (!ocupadas.contains('${fila[pk]}')) fila,
            ];
      for (final fila in filas) {
        // `<Never>`: la tabla llega como `TableInfo<Table, Object?>` y Drift verifica en runtime
        // el tipo de su fila; un insertable de `Never` es subtipo de cualquiera.
        await into(tabla).insertOnConflictUpdate(RawValuesInsertable<Never>(_valores(tabla, fila)));
        if (entidad == 'ubicacion') await _guardarMarcaDeUnion(fila);
      }
      final ids = [
        for (final fila in filas)
          if (fila[pk] case final id?) '$id',
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
    // Sin watermark (la `server_row` de un LWW) se deja el que había.
    if (watermark != null) {
      await into(
        syncWatermarks,
      ).insertOnConflictUpdate(SyncWatermarksCompanion.insert(scope: scope, watermark: watermark));
    }
  });

  /// La marca de unión de una `ubicacion` que bajó (HU-UBI-006, «Marca unión» y «Marca local»,
  /// contrato §2.3): el servidor manda `unida_a_id` junto con la fila (el id de la ubicación a la que
  /// se unió, o `null`), que **no es una columna de `ubicacion`**, y el teléfono la guarda en su tabla
  /// aparte `ubicacion_unida`, que nunca sube. Con `null` se borra la marca; si la fila no trae la
  /// clave (un servidor que todavía no la manda), no se toca.
  Future<void> _guardarMarcaDeUnion(Map<String, Object?> fila) async {
    if (!fila.containsKey('unida_a_id')) return;
    final id = fila['id'];
    if (id is! String) return;
    final unidas = attachedDatabase.ubicacionesUnidas;
    final unidaA = fila['unida_a_id'];
    if (unidaA is String && unidaA.isNotEmpty) {
      await into(unidas).insertOnConflictUpdate(
        UbicacionesUnidasCompanion.insert(ubicacionId: id, unidaAId: unidaA),
      );
    } else {
      await (delete(unidas)..where((u) => u.ubicacionId.equals(id))).go();
    }
  }

  /// Con un `area_reset` de [tabla]: todo lo que el teléfono tiene de ella pasa a esperar volver a
  /// bajar, menos lo que ya se sabe afuera y lo que tiene escrituras en la cola sin terminar: las de
  /// su propio job y las que [unapplied] nombra (un espacio que movió una unión todavía sin subir).
  Future<void> _ponerALaEspera(TableInfo<Table, Object?> tabla, UnappliedRows? unapplied) async {
    final pk = _pkDe(tabla);
    final entidad = tabla.actualTableName;
    await customStatement(
      'INSERT OR IGNORE INTO sync_fuera_del_area (entidad, fila_id, confirmada) '
      'SELECT ?, t."$pk", 0 FROM "$entidad" t '
      'WHERE NOT EXISTS (SELECT 1 FROM sync_queue q WHERE q.entity = ? AND q.row_pk = t."$pk" '
      "AND q.state <> 'DONE')",
      [entidad, entidad],
    );
    if (unapplied == null) return;
    final aLaEspera = [
      for (final f in await (select(
        syncFueraDelArea,
      )..where((f) => f.entidad.equals(entidad) & f.confirmada.equals(false))).get())
        f.filaId,
    ];
    if (aLaEspera.isEmpty) return;
    final ocupadas = (await unapplied(entidad, aLaEspera)).toList();
    for (var i = 0; i < ocupadas.length; i += 500) {
      final tramo = ocupadas.sublist(i, i + 500 > ocupadas.length ? ocupadas.length : i + 500);
      await (delete(syncFueraDelArea)..where(
            (f) => f.entidad.equals(entidad) & f.confirmada.equals(false) & f.filaId.isIn(tramo),
          ))
          .go();
    }
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

  /// §2.3, «Venta tarde» (`merged`, contrato §6.1): el servidor juntó el vínculo [de] con el
  /// vínculo [a] que ya tenía y no guardó el primero. Lo local que nombraba a [de] pasa a [a],
  /// todo en una transacción y **sin borrar nada**:
  ///
  /// - las visitas, las agendas y las ventas que lo nombran (`espacio_persona_id`), ya subidas o no:
  ///   la venta no baja del servidor (un solo escritor), así que sin esto quedaría colgada de un id
  ///   que el servidor no tiene;
  /// - la fila del vínculo misma: pasa a llamarse [a] si el teléfono todavía no tiene un vínculo
  ///   con ese id. Si ya lo tiene (bajó del servidor), la de [de] queda como está, sin baja local y
  ///   sin encolar nada (decisión del 25/11, mapa §2: queda en el espacio fundido, que el pull da de
  ///   baja, y sus hijos ya cuelgan de [a]).
  ///
  /// **La cola no se reescribe** (decisión del 25/11, mapa §2): lo encolado que nombra a [de] sale
  /// como estaba, y el servidor redirige el id viejo (migración 0064, `redirigir_vinculo`). Tampoco
  /// los jobs del vínculo mismo: el servidor pasa un `update` o un `delete` del id viejo al que quedó
  /// (contrato §2.3, «Edición tarde»). No encola nada. Idempotente: sin nada que nombre a [de], no
  /// hace nada. Una entidad sin referencias conocidas tampoco hace nada: el job ya está aplicado en
  /// el servidor y no se tiene que trabar la cola por esto.
  @override
  Future<void> reapuntar(String entity, {required String de, required String a}) async {
    _tabla(entity);
    if (de == a) return;
    if (entity != _vinculo) return;
    final db = attachedDatabase;
    await transaction(() async {
      await (db.update(db.visitas)..where((x) => x.espacioPersonaId.equals(de))).write(
        VisitasCompanion(espacioPersonaId: Value(a)),
      );
      await (db.update(db.agendas)..where((x) => x.espacioPersonaId.equals(de))).write(
        AgendasCompanion(espacioPersonaId: Value(a)),
      );
      await (db.update(db.ventas)..where((x) => x.espacioPersonaId.equals(de))).write(
        VentasCompanion(espacioPersonaId: Value(a)),
      );
      final yaEsta = await (db.select(
        db.espacioPersonas,
      )..where((x) => x.id.equals(a))).getSingleOrNull();
      if (yaEsta == null) {
        await (db.update(
          db.espacioPersonas,
        )..where((x) => x.id.equals(de))).write(EspacioPersonasCompanion(id: Value(a)));
      }
    });
  }

  static const _vinculo = 'espacio_persona';

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
