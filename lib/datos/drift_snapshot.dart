// La DB local vista como archivo: exportar para el backup, reemplazar para el
// restore (ADR-003, §7).

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sync_engine/sync_engine.dart';

import 'db.dart';

class DriftSnapshot implements SnapshotPort {
  DriftSnapshot(this._db);

  final DbLocal _db;

  @override
  Future<List<int>> export({DateTime? since}) async {
    final consulta = _db.select(_db.filas);
    if (since != null) {
      consulta.where((t) => t.actualizadoEn.isBiggerOrEqualValue(since));
    }
    final filas = await consulta.get();

    // **`sync_queue` va en el backup** (§7 fase 1). Los jobs encolados al
    // momento del backup tienen que volver a existir del otro lado: si no, un
    // colportor que restaura en un celular nuevo pierde justo las ventas que
    // todavía no habían subido, que son las únicas que no están en el servidor.
    //
    // Los `DONE` no: ya están arriba, y solo harían pesar el backup.
    final cola = await (_db.select(_db.syncQueue)
          ..where((t) => t.state.isNotValue('DONE')))
        .get();

    // Los watermarks también: son de dónde arranca la reconciliación de §7. Sin
    // ellos, el dispositivo restaurado vuelve a bajar la réplica entera.
    final watermarks = await _db.select(_db.watermarks).get();

    return utf8.encode(jsonEncode({
      'version': 1,
      'desde': since?.toIso8601String(),
      'filas': [
        for (final f in filas)
          {
            'entidad': f.entidad,
            'id': f.id,
            'datos': f.datos,
            'actualizado_en': f.actualizadoEn.toIso8601String(),
          }
      ],
      'sync_queue': [
        for (final j in cola)
          {
            'id': j.id,
            'client_op_id': j.clientOpId,
            'entity': j.entity,
            'op': j.op,
            'payload': j.payload,
            'sync_version': j.syncVersion,
            'created_at': j.createdAt.toIso8601String(),
            'state': j.state,
            'code': j.code,
            'message': j.message,
          }
      ],
      'watermarks': [
        for (final w in watermarks) {'scope': w.scope, 'valor': w.valor}
      ],
    }));
  }

  @override
  Future<void> restore(List<List<int>> payloadsInOrder) =>
      // Todo en una transacción. El contrato pide que un restore que falla a la
      // mitad no deje al colportor sin la DB que tenía; una transacción da
      // exactamente eso —o entra el estado completo, o queda el anterior— sin
      // el archivo temporal y el swap, que en SQLite además obligan a cerrar y
      // reabrir la conexión con la app corriendo encima.
      _db.transaction(() async {
        await _db.delete(_db.filas).go();
        await _db.delete(_db.syncQueue).go();
        await _db.delete(_db.watermarks).go();

        // Base primero y cada incremental encima, en orden: la cadena. Un
        // incremental posterior pisa la misma (entidad, id) con su versión más
        // nueva, que es justo lo que tiene que pasar.
        for (final payload in payloadsInOrder) {
          final m = jsonDecode(utf8.decode(payload)) as Map<String, Object?>;

          for (final f in (m['filas'] as List? ?? const [])) {
            final fila = (f as Map).cast<String, Object?>();
            await _db.into(_db.filas).insertOnConflictUpdate(
                  FilasCompanion.insert(
                    entidad: '${fila['entidad']}',
                    id: '${fila['id']}',
                    datos: '${fila['datos']}',
                    actualizadoEn:
                        DateTime.parse('${fila['actualizado_en']}').toUtc(),
                  ),
                );
          }

          for (final j in (m['sync_queue'] as List? ?? const [])) {
            final job = (j as Map).cast<String, Object?>();
            await _db.into(_db.syncQueue).insertOnConflictUpdate(
                  SyncQueueCompanion.insert(
                    id: '${job['id']}',
                    clientOpId: '${job['client_op_id']}',
                    entity: '${job['entity']}',
                    op: '${job['op']}',
                    payload: '${job['payload']}',
                    syncVersion: Value(job['sync_version'] as int?),
                    createdAt: DateTime.parse('${job['created_at']}').toUtc(),
                    // Lo que estaba IN_FLIGHT vuelve como PENDING: el ciclo que
                    // lo tenía en la mano murió con el dispositivo viejo y nadie
                    // lo va a reclamar. Reenviarlo es seguro por el
                    // `client_op_id` (§5.3).
                    state: job['state'] == 'IN_FLIGHT'
                        ? 'PENDING'
                        : '${job['state']}',
                    code: Value('${job['code'] ?? ''}'),
                    message: Value('${job['message'] ?? ''}'),
                  ),
                );
          }

          for (final w in (m['watermarks'] as List? ?? const [])) {
            final wm = (w as Map).cast<String, Object?>();
            await _db.into(_db.watermarks).insertOnConflictUpdate(
                  WatermarksCompanion.insert(
                    scope: '${wm['scope']}',
                    valor: '${wm['valor']}',
                  ),
                );
          }
        }
      });
}
