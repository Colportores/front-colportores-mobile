import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../models/zona_model.dart';

/// Una zona con la campaña y la ciudad de su `campania_ciudad`.
typedef ZonaDeCiudad = ({ZonaModel zona, String campaniaId, String ciudadId});

/// Lectura de las zonas replicadas del canal de catálogo (`zona` + `campania_ciudad`).
abstract interface class ZonaLocalDataSource {
  /// Las zonas de [ciudadId] vivas —la zona y su `campania_ciudad` sin baja—, ordenadas por `id`.
  Future<List<ZonaDeCiudad>> vivasDeCiudad(String ciudadId);
}

/// [ZonaLocalDataSource] sobre la DB local (Drift).
final class ZonaLocalDataSourceDrift implements ZonaLocalDataSource {
  ZonaLocalDataSourceDrift(this._db);

  final AppDatabase _db;

  @override
  Future<List<ZonaDeCiudad>> vivasDeCiudad(String ciudadId) async {
    final zona = _db.zonas;
    final campaniaCiudad = _db.campaniasCiudad;
    final consulta =
        _db.select(zona).join([
            innerJoin(campaniaCiudad, campaniaCiudad.id.equalsExp(zona.campaniaCiudadId)),
          ])
          ..where(
            zona.deletedAt.isNull() &
                campaniaCiudad.deletedAt.isNull() &
                campaniaCiudad.ciudadId.equals(ciudadId),
          )
          ..orderBy([OrderingTerm.asc(zona.id)]);
    return [
      for (final fila in await consulta.get())
        (
          zona: ZonaModel.fromFila(fila.readTable(zona)),
          campaniaId: fila.readTable(campaniaCiudad).campaniaId,
          ciudadId: fila.readTable(campaniaCiudad).ciudadId,
        ),
    ];
  }
}
