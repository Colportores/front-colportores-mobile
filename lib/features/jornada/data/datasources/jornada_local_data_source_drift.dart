import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../models/jornada_model.dart';
import 'jornada_local_data_source.dart';
import 'jornadas_table.dart';

part 'jornada_local_data_source_drift.g.dart';

/// [JornadaLocalDataSource] sobre la tabla `jornada` de la DB cifrada ([Jornadas]).
///
/// Es el DAO de la tabla (`@DriftAccessor`): recibe el [AppDatabase] que abrió `DatabaseHelper` y
/// traduce [JornadaModel] ↔ [JornadaFila]. La traducción vive acá y no en el modelo para que
/// `JornadaModel` no dependa de Drift.
@DriftAccessor(tables: [Jornadas])
final class JornadaLocalDataSourceDrift extends DatabaseAccessor<AppDatabase>
    with _$JornadaLocalDataSourceDriftMixin
    implements JornadaLocalDataSource {
  JornadaLocalDataSourceDrift(super.attachedDatabase);

  @override
  Future<JornadaModel?> obtenerActiva(String colportorId) async {
    final fila = await _consultaActiva(colportorId).getSingleOrNull();
    return fila == null ? null : _aModelo(fila);
  }

  /// Comprobar e insertar van en una sola transacción: Drift no deja correr dos transacciones a la
  /// vez sobre la misma DB, así que dos inicios casi simultáneos se serializan y el segundo ya ve
  /// la jornada del primero. Si otra conexión escribiera en el medio, SQLite aborta una de las dos
  /// transacciones antes que dejar pasar la segunda jornada.
  @override
  Future<void> insertar(JornadaModel jornada) => transaction(() async {
    final activa = await _consultaActiva(jornada.colportorId).getSingleOrNull();
    if (activa != null) throw const JornadaActivaExistenteException();
    await into(jornadas).insert(_aFila(jornada));
  });

  /// Un solo `UPDATE … WHERE fin IS NULL AND deleted_at IS NULL`: la comprobación y la escritura
  /// son la misma sentencia, así que un segundo cierre casi simultáneo no encuentra la fila
  /// abierta y lanza [JornadaNoAbiertaException] en vez de pisar el `fin` del primero.
  @override
  Future<void> finalizar(JornadaModel jornada) async {
    final fin = jornada.fin;
    if (fin == null) throw ArgumentError.value(jornada.id, 'jornada', 'no trae fin');
    final actualizadas =
        await (update(jornadas)..where(
              (j) =>
                  j.id.equals(jornada.id) &
                  j.colportorId.equals(jornada.colportorId) &
                  j.fin.isNull() &
                  j.deletedAt.isNull(),
            ))
            .write(
              JornadasCompanion(fin: Value(fin), updatedAt: Value(jornada.auditoria.updatedAt)),
            );
    if (actualizadas == 0) throw const JornadaNoAbiertaException();
  }

  /// La jornada sin `fin` y sin soft delete del colportor. `limit(1)`: la regla de una sola activa
  /// la sostiene [insertar], pero una recuperación de dispositivo (`engine.recover()`,
  /// contrato-sync-engine §7) podría dejar una segunda abierta —`jornada` no baja por pull: es
  /// `push` sin `alsoPull`, §2-§3—; en ese caso se devuelve la más reciente en vez de fallar.
  Selectable<JornadaFila> _consultaActiva(String colportorId) => (select(jornadas)
    ..where((j) => j.colportorId.equals(colportorId) & j.fin.isNull() & j.deletedAt.isNull())
    ..orderBy([(j) => OrderingTerm.desc(j.inicio)])
    ..limit(1));

  static JornadasCompanion _aFila(JornadaModel jornada) => JornadasCompanion.insert(
    id: jornada.id,
    colportorId: jornada.colportorId,
    inicio: jornada.inicio,
    fin: Value(jornada.fin),
    acompananteId: Value(jornada.acompananteId),
    tipoAcompanamiento: Value(jornada.tipoAcompanamiento),
    totalVisitas: Value(jornada.totalVisitas),
    totalVentas: Value(jornada.totalVentas),
    createdAt: jornada.auditoria.createdAt,
    updatedAt: jornada.auditoria.updatedAt,
    createdBy: Value(jornada.auditoria.createdBy),
    deletedAt: Value(jornada.auditoria.deletedAt),
    syncVersion: Value(jornada.auditoria.syncVersion),
  );

  static JornadaModel _aModelo(JornadaFila fila) => JornadaModel(
    id: fila.id,
    colportorId: fila.colportorId,
    inicio: fila.inicio,
    fin: fila.fin,
    acompananteId: fila.acompananteId,
    tipoAcompanamiento: fila.tipoAcompanamiento,
    totalVisitas: fila.totalVisitas,
    totalVentas: fila.totalVentas,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );
}
