import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/zona_ubicable.dart';
import '../../domain/repositories/zona_repository.dart';
import '../../domain/value_objects/geometria_zona.dart';
import '../datasources/zona_local_data_source.dart';

/// Implementación de [ZonaRepository] sobre [ZonaLocalDataSource].
///
/// Una zona cuya forma no es un `Polygon`/`MultiPolygon` legible se saltea con un aviso en el log:
/// el servidor valida la forma al guardarla, así que sería un dato roto, y la zona del punto la
/// vuelve a calcular el servidor igual. Cualquier excepción de la lectura es `FailureInesperado`.
/// Loguea en `[DB]` solo UUIDs.
final class ZonaRepositoryImpl implements ZonaRepository {
  ZonaRepositoryImpl(this._local, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final ZonaLocalDataSource _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, List<ZonaUbicable>>> vivasDeCiudad(String ciudadId) async {
    try {
      final zonas = <ZonaUbicable>[];
      for (final (:zona, :campaniaId, ciudadId: ciudad) in await _local.vivasDeCiudad(ciudadId)) {
        final geometria = GeometriaZona.desdeGeojson(zona.poligonoGeojson);
        if (geometria == null) {
          _log.warn(
            LogModulo.db,
            'ZONA_FORMA_ILEGIBLE',
            'zona salteada: su forma no se puede leer',
            {'zona_id': zona.id},
          );
          continue;
        }
        zonas.add(
          ZonaUbicable(
            zonaId: zona.id,
            campaniaId: campaniaId,
            ciudadId: ciudad,
            geometria: geometria,
          ),
        );
      }
      return Right(zonas);
    } on Object catch (e, st) {
      _log.error(
        LogModulo.db,
        'ZONAS_LEER_FAIL',
        'no se pudieron leer las zonas de la ciudad',
        {'ciudad_id': ciudadId},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }
}
