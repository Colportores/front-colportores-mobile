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
/// El restore es de HU-SYNC-006 (#186): hasta entonces [restore] falla a propósito, porque
/// aplicar medio backup sin el reemplazo atómico de la DB sería peor que no aplicarlo.
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
  Future<void> restore(List<List<int>> payloadsInOrder) =>
      throw UnsupportedError('el restore de la DB es de HU-SYNC-006 (#186)');
}
