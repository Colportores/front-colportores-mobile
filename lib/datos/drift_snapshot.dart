import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sync_engine/sync_engine.dart';

import '../core/database/app_database.dart';

/// [SnapshotPort] sobre la DB local: lo que el backup E2E lleva (ADR-003, ADR-006, HU-SYNC-005).
///
/// **Qué entra.** Lo que no se puede volver a bajar del servidor: las tablas `push` (lo que escribió
/// el colportor; si todavía no subió, no está en ningún otro lado) y las `local` (personas, notas,
/// historial: solo viven en el teléfono, Ley 18.331), más la cola de sync, porque los jobs
/// encolados al momento del backup tienen que volver a existir (contrato §7, fase 1). Las
/// réplicas de solo lectura (`pull`) no entran: el pull las reconstruye. `sesion_usuario` tampoco:
/// es de la sesión de este teléfono y se rearma al iniciar sesión.
///
/// **Formato.** Un JSON (el [CompressingCrypto] del paquete lo comprime y lo cifra después):
///
/// ```json
/// {"formato": 1, "esquema": 20, "completo": false, "desde": "2026-11-02T22:00:00.000Z",
///  "exportadoEn": "2026-11-03T22:00:00.000Z",
///  "tablas": {"venta": {"modo": "upsert", "filas": [{"id": "…", …}]},
///             "sync_queue": {"modo": "replace", "filas": […]}}}
/// ```
///
/// `esquema` es la versión del esquema de la DB que lo exportó: el restore compara con la de la app
/// y no restaura un backup de una versión más nueva (HU-SYNC-006).
///
/// Las filas van **crudas**, como están en SQLite (fechas en epoch ms, sin pasar por los
/// conversores): es el mismo formato que el restore tiene que volver a escribir, y no hay un
/// segundo mapeo que pueda diferir. Los BLOB, si algún día una tabla los tiene, van como
/// `{"\$b64": "…"}`.
///
/// **Incremental.** `since` filtra por `updated_at` (en `audit_log`, por `creado_en`): una fila
/// entra si se escribió desde ese instante. Las bajas son lógicas (`deleted_at`), así que una baja
/// también mueve `updated_at` y viaja. Las tablas sin fecha de escritura (la cola, los pares
/// decididos, el historial de avisos) van enteras con `modo: replace`: son chicas y se compactan
/// o se borran, así que el restore las reemplaza en vez de sumarles.
///
/// **Restore** (HU-SYNC-006, #186). [restore] aplica una cadena (la base y sus incrementales, en
/// orden) y [restoreChains] fusiona varias, las de cada teléfono que la persona tuvo (decisión de
/// Cristian, 03/11, «Varios resp.»). Todo en **una sola transacción**: o entra todo o la DB queda como
/// estaba. Antes de tocar nada se lee y valida cada payload (formato y esquema), así que un respaldo
/// ilegible o de una versión más nueva ni empieza.
///
/// La fusión es por fecha de fila: en las tablas con fecha de escritura (`updated_at`, o `creado_en` en
/// `audit_log`) una fila que ya está solo se pisa por otra **igual o más nueva**; en las que van
/// enteras (`modo: replace`: la cola, los pares decididos…) se junta la última foto de cada cadena,
/// sin perder los trabajos de ninguna. Las columnas que el payload trae y esta versión de la app ya no
/// tiene se ignoran.
final class DriftSnapshot implements SnapshotPort {
  DriftSnapshot(this._db, {required this._tablas, DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now().toUtc());

  /// El formato del payload. Sube si cambia la forma, para que el restore sepa qué leer.
  static const formato = 1;

  /// Las tablas que se leen (nombres de tabla de SQLite).
  final Set<String> _tablas;
  final AppDatabase _db;
  final DateTime Function() _clock;

  /// La columna de la fecha de escritura de cada tabla; sin entrada, no tiene.
  static const _columnaDeFecha = {'audit_log': 'creado_en'};

  @override
  Future<List<int>> export({DateTime? since}) async {
    final exportadoEn = _clock();
    final tablas = <String, Object?>{};

    // Una sola transacción: el backup ve la DB en un único instante, no una tabla de antes de una
    // venta y otra de después.
    await _db.transaction(() async {
      for (final tabla in _db.allTables) {
        final nombre = tabla.actualTableName;
        if (!_tablas.contains(nombre)) continue;
        tablas[nombre] = await _leer(tabla, nombre, since);
      }
    });

    return utf8.encode(
      jsonEncode({
        'formato': formato,
        'esquema': _db.schemaVersion,
        'completo': since == null,
        'desde': since?.toUtc().toIso8601String(),
        'exportadoEn': exportadoEn.toUtc().toIso8601String(),
        'tablas': tablas,
      }),
    );
  }

  Future<Map<String, Object?>> _leer(
    TableInfo<Table, Object?> tabla,
    String nombre,
    DateTime? since,
  ) async {
    final columnas = {for (final c in tabla.$columns) c.name};
    final fecha =
        _columnaDeFecha[nombre] ?? (columnas.contains('updated_at') ? 'updated_at' : null);

    final filtrar = since != null && fecha != null;
    final filas = await _db
        .customSelect(
          'SELECT * FROM "$nombre"${filtrar ? ' WHERE "$fecha" >= ?' : ''}',
          variables: [if (filtrar) Variable<int>(since.toUtc().millisecondsSinceEpoch)],
          readsFrom: {tabla},
        )
        .get();

    return {
      // Sin fecha de escritura no hay forma de saber qué cambió: va entera y reemplaza.
      'modo': fecha == null ? 'replace' : 'upsert',
      'filas': [for (final f in filas) _aJson(f.data)],
    };
  }

  Map<String, Object?> _aJson(Map<String, Object?> fila) => {
    for (final e in fila.entries)
      e.key: switch (e.value) {
        final Uint8List bytes => {r'$b64': base64Encode(bytes)},
        final v => v,
      },
  };

  @override
  Future<void> restore(List<List<int>> payloadsInOrder) => restoreChains([payloadsInOrder]);

  /// Fusiona varias cadenas de respaldo en la DB (ver la doc de la clase). Cada cadena va de la base a
  /// la punta; el orden entre cadenas desempata las filas con la misma fecha (gana la posterior), así
  /// que conviene pasarlas de la más vieja a la más nueva.
  ///
  /// Lanza [SnapshotNewerSchemaException] si algún payload viene de una versión más nueva de la
  /// DB, y [SnapshotUnreadableException] si no se puede leer o no se puede aplicar. En los dos casos la
  /// DB queda como estaba.
  @override
  Future<void> restoreChains(List<List<List<int>>> cadenas) async {
    final leidas = [
      for (final cadena in cadenas) [for (final payload in cadena) _leerPayload(payload)],
    ];

    try {
      await _db.transaction(() async {
        // Las filas llegan por tabla y no en orden de dependencia: las claves foráneas se miran al
        // confirmar, no fila por fila.
        await _db.customStatement('PRAGMA defer_foreign_keys = ON');
        final porTabla = {for (final t in _db.allTables) t.actualTableName: t};

        // Las tablas «replace» se juntan antes de escribir: la última foto de cada cadena, todas
        // sumadas.
        final enteras = <String, List<Map<String, Object?>>>{};
        for (final cadena in leidas) {
          final ultimaFoto = <String, List<Map<String, Object?>>>{};
          for (final payload in cadena) {
            for (final MapEntry(key: nombre, value: tabla) in payload.tablas.entries) {
              if (tabla.modo == 'replace') ultimaFoto[nombre] = tabla.filas;
            }
          }
          for (final MapEntry(key: nombre, value: filas) in ultimaFoto.entries) {
            (enteras[nombre] ??= []).addAll(filas);
          }
        }

        for (final cadena in leidas) {
          for (final payload in cadena) {
            for (final MapEntry(key: nombre, value: tabla) in payload.tablas.entries) {
              final info = porTabla[nombre];
              if (info == null || !_tablas.contains(nombre) || tabla.modo == 'replace') continue;
              for (final fila in tabla.filas) {
                await _escribir(info, nombre, fila, soloSiEsIgualOMasNueva: true);
              }
            }
          }
        }

        for (final MapEntry(key: nombre, value: filas) in enteras.entries) {
          final info = porTabla[nombre];
          if (info == null || !_tablas.contains(nombre)) continue;
          await _db.customStatement('DELETE FROM "$nombre"');
          for (final fila in filas) {
            await _escribir(info, nombre, fila, soloSiEsIgualOMasNueva: false);
          }
        }
      });
    } on Object catch (e) {
      // Solo el tipo: el mensaje de SQLite puede citar un valor de la fila.
      throw SnapshotUnreadableException('no se pudo aplicar (${e.runtimeType})');
    }
  }

  _PayloadLeido _leerPayload(List<int> bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on Object {
      throw const SnapshotUnreadableException('no es JSON');
    }
    if (json is! Map<String, Object?>) throw const SnapshotUnreadableException('no es un objeto');
    final formatoDelPayload = json['formato'];
    final esquema = json['esquema'];
    final tablas = json['tablas'];
    if (formatoDelPayload is! int || esquema is! int || tablas is! Map<String, Object?>) {
      throw const SnapshotUnreadableException('faltan campos');
    }
    if (formatoDelPayload > formato) throw const SnapshotUnreadableException('formato más nuevo');
    if (esquema > _db.schemaVersion) {
      throw SnapshotNewerSchemaException(backupSchema: esquema, appSchema: _db.schemaVersion);
    }
    final resultado = <String, _TablaLeida>{};
    for (final MapEntry(key: nombre, value: tabla) in tablas.entries) {
      if (tabla is! Map<String, Object?>) throw const SnapshotUnreadableException('tabla rota');
      final filas = tabla['filas'];
      if (filas is! List) throw const SnapshotUnreadableException('tabla sin filas');
      resultado[nombre] = _TablaLeida(
        modo: tabla['modo'] == 'replace' ? 'replace' : 'upsert',
        filas: [
          for (final f in filas)
            if (f is Map<String, Object?>)
              f
            else
              throw const SnapshotUnreadableException('fila rota'),
        ],
      );
    }
    return _PayloadLeido(resultado);
  }

  Future<void> _escribir(
    TableInfo<Table, Object?> tabla,
    String nombre,
    Map<String, Object?> fila, {
    required bool soloSiEsIgualOMasNueva,
  }) async {
    final columnas = {for (final c in tabla.$columns) c.name};
    final presentes = [
      for (final k in fila.keys)
        if (columnas.contains(k)) k,
    ];
    if (presentes.isEmpty) return;
    final valores = <Object?>[
      for (final k in presentes)
        switch (fila[k]) {
          final Map<String, Object?> m when m.containsKey(r'$b64') => base64Decode(
            m[r'$b64']! as String,
          ),
          final bool b => b ? 1 : 0,
          final v => v,
        },
    ];
    final lista = presentes.map((c) => '"$c"').join(', ');
    final marcas = List.filled(presentes.length, '?').join(', ');
    final claves = [for (final c in tabla.$primaryKey) c.name];
    final fecha =
        _columnaDeFecha[nombre] ?? (columnas.contains('updated_at') ? 'updated_at' : null);

    final sinFecha = fecha == null || !presentes.contains(fecha);
    if (!soloSiEsIgualOMasNueva || claves.isEmpty || sinFecha) {
      await _db.customStatement(
        'INSERT OR REPLACE INTO "$nombre" ($lista) VALUES ($marcas)',
        valores,
      );
      return;
    }
    final conflicto = claves.map((c) => '"$c"').join(', ');
    final cambios = presentes
        .where((c) => !claves.contains(c))
        .map((c) => '"$c" = excluded."$c"')
        .join(', ');
    if (cambios.isEmpty) {
      await _db.customStatement(
        'INSERT OR IGNORE INTO "$nombre" ($lista) VALUES ($marcas)',
        valores,
      );
      return;
    }
    await _db.customStatement(
      'INSERT INTO "$nombre" ($lista) VALUES ($marcas) '
      'ON CONFLICT ($conflicto) DO UPDATE SET $cambios '
      'WHERE excluded."$fecha" >= "$nombre"."$fecha"',
      valores,
    );
  }
}

final class _PayloadLeido {
  const _PayloadLeido(this.tablas);

  final Map<String, _TablaLeida> tablas;
}

final class _TablaLeida {
  const _TablaLeida({required this.modo, required this.filas});

  final String modo;
  final List<Map<String, Object?>> filas;
}
