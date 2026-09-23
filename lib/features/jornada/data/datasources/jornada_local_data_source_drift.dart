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

  /// La jornada sin `fin` y sin soft delete del colportor. `limit(1)`: la regla de una sola activa
  /// la sostiene [insertar], pero un pull de sync podría traer una segunda abierta desde otro
  /// dispositivo; en ese caso se devuelve la más reciente en vez de fallar.
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
