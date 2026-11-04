import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../agenda/domain/entities/visita.dart';
import '../../domain/entities/ultima_visita_del_espacio.dart';
import '../../domain/services/lector_ultima_visita_de_la_ubicacion.dart';

/// [LectorUltimaVisitaDeLaUbicacion] sobre la tabla `visita` de la DB local: la visita de fecha más
/// reciente de cualquier espacio de la ubicación, sin las dadas de baja. A igual fecha manda la creada
/// después (`created_at`, y a igual, el `id`), igual que [UltimaVisitaDelEspacioDrift]. Solo lee.
final class UltimaVisitaDeLaUbicacionDrift implements LectorUltimaVisitaDeLaUbicacion {
  UltimaVisitaDeLaUbicacionDrift(this._db);

  final AppDatabase _db;

  @override
  Future<UltimaVisitaDelEspacio?> de(String ubicacionId) async {
    final visitas = _db.visitas;
    final consulta =
        _db.select(visitas).join([
            innerJoin(_db.espacios, _db.espacios.id.equalsExp(visitas.espacioId)),
          ])
          ..where(_db.espacios.ubicacionId.equals(ubicacionId) & visitas.deletedAt.isNull())
          ..orderBy([
            OrderingTerm.desc(visitas.fecha),
            OrderingTerm.desc(visitas.createdAt),
            OrderingTerm.desc(visitas.id),
          ])
          ..limit(1);
    final fila = (await consulta.getSingleOrNull())?.readTable(visitas);
    if (fila == null) return null;
    return UltimaVisitaDelEspacio(
      resultado: TipoResultadoVisita.desdeCodigo(fila.tipoResultado),
      fecha: fila.fecha,
    );
  }
}
