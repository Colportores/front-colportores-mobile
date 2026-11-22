import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

/// Lo que «Mapas offline» necesita de las réplicas para nombrar el lugar donde trabaja el colportor.
typedef DatosDelLugar = ({Map<String, String> nombresDeZonas, String? departamento});

/// Lectura local de los nombres que el catálogo de paquetes no trae (HU-SYNC-010, #619): el nombre de
/// la zona (los paquetes de zona no lo llevan: el catálogo es público) y el departamento de la ciudad.
abstract interface class LugarDeTrabajoLocalDataSource {
  /// El nombre de cada zona viva de [zonaIds] y el departamento de la ciudad [ciudadId] (`null` si la
  /// ciudad no lo tiene cargado o no está en el teléfono). Una zona dada de baja no aparece.
  Future<DatosDelLugar> leer({required Set<String> zonaIds, required String ciudadId});
}

/// [LugarDeTrabajoLocalDataSource] sobre la DB local (Drift): lee las réplicas `zona` y `ciudad` en una
/// transacción, para que un pull que escribe en medio no deje el nombre de una y el departamento de
/// otra a medias.
final class LugarDeTrabajoLocalDataSourceDrift implements LugarDeTrabajoLocalDataSource {
  LugarDeTrabajoLocalDataSourceDrift(this._db);

  final AppDatabase _db;

  @override
  Future<DatosDelLugar> leer({required Set<String> zonaIds, required String ciudadId}) =>
      _db.transaction(() async {
        final zonas = zonaIds.isEmpty
            ? const <ZonaFila>[]
            : await (_db.select(
                _db.zonas,
              )..where((z) => z.id.isIn(zonaIds) & z.deletedAt.isNull())).get();
        final ciudad = await (_db.select(
          _db.ciudades,
        )..where((c) => c.id.equals(ciudadId))).getSingleOrNull();
        return (
          nombresDeZonas: {for (final z in zonas) z.id: z.nombre},
          departamento: ciudad?.departamento,
        );
      });
}
