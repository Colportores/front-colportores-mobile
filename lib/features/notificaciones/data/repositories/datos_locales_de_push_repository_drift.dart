import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/fecha_utc_converter.dart';
import '../../domain/repositories/datos_locales_de_push_repository.dart';

/// [DatosLocalesDePushRepository] sobre la DB local cifrada.
final class DatosLocalesDePushRepositoryDrift implements DatosLocalesDePushRepository {
  DatosLocalesDePushRepositoryDrift(this._db);

  final AppDatabase _db;

  @override
  Future<String?> nombreDeCampania(String campaniaId) async {
    final fila = await (_db.select(
      _db.campanias,
    )..where((c) => c.id.equals(campaniaId))).getSingleOrNull();
    return _conTexto(fila?.nombre);
  }

  @override
  Future<String?> nombreDeZona(String zonaId) async {
    final fila = await (_db.select(_db.zonas)..where((z) => z.id.equals(zonaId))).getSingleOrNull();
    return _conTexto(fila?.nombre);
  }

  @override
  Future<int> visitasProgramadasParaManana(DateTime ahora) async {
    final hoy = ahora.toLocal();
    final desde = DateTime(hoy.year, hoy.month, hoy.day + 1);
    final hasta = DateTime(hoy.year, hoy.month, hoy.day + 2);
    const conversor = FechaUtcConverter();
    final filas =
        await (_db.select(_db.agendas)..where(
              (a) =>
                  a.estado.equals('PROGRAMADA') &
                  a.deletedAt.isNull() &
                  a.fechaProgramada.isBiggerOrEqualValue(conversor.toSql(desde)) &
                  a.fechaProgramada.isSmallerThanValue(conversor.toSql(hasta)),
            ))
            .get();
    return filas.length;
  }

  String? _conTexto(String? nombre) {
    final limpio = nombre?.trim();
    return limpio == null || limpio.isEmpty ? null : limpio;
  }
}
