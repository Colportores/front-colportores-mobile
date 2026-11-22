import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../agenda/domain/entities/visita.dart';
import '../../domain/entities/ultima_visita_del_espacio.dart';
import '../../domain/services/lector_ultima_visita_del_espacio.dart';

/// [LectorUltimaVisitaDelEspacio] sobre la tabla `visita` de la DB local (índice `visita_espacio_idx`):
/// la visita de fecha más reciente del espacio que no esté dada de baja. Solo lee.
///
/// A igual fecha manda la creada después (`created_at`, y a igual, el `id`), para que dos visitas del
/// mismo milisegundo no se turnen entre una lectura y otra.
final class UltimaVisitaDelEspacioDrift implements LectorUltimaVisitaDelEspacio {
  UltimaVisitaDelEspacioDrift(this._db);

  final AppDatabase _db;

  @override
  Stream<UltimaVisitaDelEspacio?> observar(String espacioId) {
    final consulta = _db.select(_db.visitas)
      ..where((v) => v.espacioId.equals(espacioId) & v.deletedAt.isNull())
      ..orderBy([
        (v) => OrderingTerm.desc(v.fecha),
        (v) => OrderingTerm.desc(v.createdAt),
        (v) => OrderingTerm.desc(v.id),
      ])
      ..limit(1);
    return consulta.watchSingleOrNull().map(
      (fila) => fila == null
          ? null
          : UltimaVisitaDelEspacio(
              resultado: TipoResultadoVisita.desdeCodigo(fila.tipoResultado),
              fecha: fila.fecha,
            ),
    );
  }
}
