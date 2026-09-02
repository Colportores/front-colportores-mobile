// Las tablas de negocio y los watermarks, sobre Drift.

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:sync_engine/sync_engine.dart';

import 'db.dart';

class DriftLocalStore implements LocalStorePort {
  DriftLocalStore(this._db, {DateTime Function()? reloj})
      : _reloj = reloj ?? (() => DateTime.now().toUtc());

  final DbLocal _db;
  final DateTime Function() _reloj;

  @override
  Future<void> applyDelta(
    Map<String, List<Map<String, Object?>>> rows, {
    required String scope,
    required String watermark,
  }) =>
      // Una sola transacción, y el watermark adentro (§10). Si aplicar falla, el
      // watermark no avanza y el próximo pull vuelve a traer lo mismo. Dos
      // operaciones separadas dejarían la puerta abierta a avanzar el watermark
      // sobre filas que no se escribieron: el hueco se volvería permanente.
      _db.transaction(() async {
        final ahora = _reloj();

        for (final MapEntry(key: entidad, value: filas) in rows.entries) {
          for (final fila in filas) {
            final id = fila['id'];
            if (id == null) {
              // Sin PK no hay forma de saber si es una fila nueva o una que ya
              // estaba. Guardarla con un id inventado duplicaría la fila en el
              // próximo delta, así que se corta acá y con nombre.
              throw StateError(
                  'el delta de "$entidad" trajo una fila sin "id": $fila');
            }

            // Un tombstone borra, no se guarda. Acumularlos haría que la DB del
            // colportor crezca con lo que ya no existe y que toda consulta
            // futura tenga que acordarse de filtrar `deleted`.
            if (fila['deleted'] == true) {
              await (_db.delete(_db.filas)
                    ..where((t) =>
                        t.entidad.equals(entidad) & t.id.equals('$id')))
                  .go();
              continue;
            }

            await _db.into(_db.filas).insertOnConflictUpdate(
                  FilasCompanion.insert(
                    entidad: entidad,
                    id: '$id',
                    datos: jsonEncode(fila),
                    actualizadoEn: ahora,
                  ),
                );
          }
        }

        // Fuera del `for`: un delta vacío **también** guarda el watermark. La
        // fase 1 de §7 lo usa para dejar puesto el del backup sin escribir
        // ninguna fila; saltearlo haría que la reconciliación arranque de cero
        // y rebaje todo lo que la DB restaurada ya tenía.
        await _db.into(_db.watermarks).insertOnConflictUpdate(
              WatermarksCompanion.insert(scope: scope, valor: watermark),
            );
      });

  @override
  Future<String?> watermarkOf(String scope) async {
    final f = await (_db.select(_db.watermarks)
          ..where((t) => t.scope.equals(scope)))
        .getSingleOrNull();
    return f?.valor;
  }

  /// Cuántas filas hay por entidad. Es lo que la UI muestra, y sale de un
  /// `group by` en la base: con la réplica en disco no hay un mapa en memoria
  /// que contar.
  Future<Map<String, int>> conteos() async {
    final cuenta = _db.filas.id.count();
    final q = _db.selectOnly(_db.filas)
      ..addColumns([_db.filas.entidad, cuenta])
      ..groupBy([_db.filas.entidad]);
    return {
      for (final f in await q.get())
        f.read(_db.filas.entidad)!: f.read(cuenta) ?? 0,
    };
  }

  /// Guarda una fila que escribió **este** dispositivo.
  ///
  /// No es parte del puerto: `applyDelta` es para lo que baja del servidor,
  /// esto es para lo que el colportor acaba de anotar. Van a la misma tabla a
  /// propósito —una venta es una venta, la haya hecho él o la haya bajado otro
  /// dispositivo—, así que las pantallas leen de un solo lado.
  ///
  /// Pensada para llamarse dentro de la misma transacción que `stage()`: o
  /// entra la fila y su job, o no entra ninguno de los dos (§3). Una venta
  /// guardada sin job es una venta que el colportor ve en pantalla y que nunca
  /// va a subir.
  Future<void> guardarLocal(String entidad, Map<String, Object?> fila) async {
    final id = fila['id'];
    if (id == null) {
      throw StateError('la fila de "$entidad" no trae "id": $fila');
    }
    await _db.into(_db.filas).insertOnConflictUpdate(
          FilasCompanion.insert(
            entidad: entidad,
            id: '$id',
            datos: jsonEncode(fila),
            actualizadoEn: _reloj(),
          ),
        );
  }

  /// Corre [accion] en una transacción de la DB local.
  ///
  /// Existe para que la app pueda meter `guardarLocal` y `stage` adentro de la
  /// misma, que es lo que el contrato pide.
  Future<T> enTransaccion<T>(Future<T> Function() accion) =>
      _db.transaction(accion);

  /// Las filas de una entidad, como las dejó el delta.
  ///
  /// No es parte del puerto: es lo que la app necesita para mostrar algo y para
  /// resolver las FK del catálogo al armar una venta.
  Future<List<Map<String, Object?>>> filasDe(String entidad) async {
    final filas = await (_db.select(_db.filas)
          ..where((t) => t.entidad.equals(entidad)))
        .get();
    return [
      for (final f in filas) (jsonDecode(f.datos) as Map).cast<String, Object?>()
    ];
  }
}
