import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/fecha_utc_converter.dart';
import '../../domain/services/ultima_visita_del_colportor.dart';

/// [UltimaVisitaDelColportor] sobre la tabla `visita` de la DB local (índice
/// `visita_colportor_idx`: colportor, fecha).
final class UltimaVisitaDelColportorDrift implements UltimaVisitaDelColportor {
  UltimaVisitaDelColportorDrift(this._db);

  final AppDatabase _db;

  @override
  Future<DateTime?> fechaAntesDe(String colportorId, DateTime antesDe) async {
    final limite = const FechaUtcConverter().toSql(antesDe);
    final consulta = _db.select(_db.visitas)
      ..where(
        (v) =>
            v.colportorId.equals(colportorId) &
            v.deletedAt.isNull() &
            v.fecha.isSmallerThanValue(limite),
      )
      ..orderBy([(v) => OrderingTerm.desc(v.fecha)])
      ..limit(1);
    final fila = await consulta.getSingleOrNull();
    return fila?.fecha;
  }
}
