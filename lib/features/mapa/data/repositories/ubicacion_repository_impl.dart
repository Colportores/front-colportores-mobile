import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/espacio.dart';
import '../../domain/entities/marcador_mapa.dart';
import '../../domain/entities/resultado_alta_ubicacion.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/repositories/ubicacion_repository.dart';
import '../../domain/services/criterio_duplicado_ubicacion.dart';
import '../../domain/value_objects/area_mapa.dart';
import '../../domain/value_objects/punto_capturado.dart';
import '../datasources/ubicacion_local_data_source.dart';
import '../models/espacio_model.dart';
import '../models/ubicacion_model.dart';

/// Implementación de [UbicacionRepository] sobre [UbicacionLocalDataSource].
///
/// - Traduce toda excepción del almacenamiento a un [Failure]; nunca deja escapar una.
/// - Devuelve entidades de dominio (`toEntity()`), no modelos.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos: ni la dirección ni las
///   coordenadas, aunque no sean datos de persona.
final class UbicacionRepositoryImpl implements UbicacionRepository {
  UbicacionRepositoryImpl(this._local, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final UbicacionLocalDataSource _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, ResultadoAltaUbicacion>> registrar(
    Ubicacion ubicacion, {
    Espacio? espacio,
    required OrigenCoordenadas origen,
    CriterioDuplicadoUbicacion? duplicados,
  }) async {
    try {
      final insercion = await _local.insertar(
        UbicacionModel.fromEntity(ubicacion),
        espacio: espacio == null ? null : EspacioModel.fromEntity(espacio),
        duplicados: duplicados,
      );
      if (insercion.yaEstaba) {
        _log.info(LogModulo.db, 'UBICACION_YA_REGISTRADA', 'el alta ya estaba hecha', {
          'ubicacion_id': ubicacion.id,
        });
        return Right(AltaRegistrada(ubicacion: insercion.ubicacion.toEntity()));
      }
      _log.info(LogModulo.db, 'UBICACION_CREADA', 'ubicación registrada', {
        'ubicacion_id': ubicacion.id,
        'espacio_id': espacio?.id,
        'user_id': ubicacion.auditoria.createdBy,
        // `coords_source` de HU-UBI-001: la tabla no tiene la columna (ver [registrar]).
        'coords_source': origen.name,
        'crear_igual': duplicados == null,
      });
      return Right(AltaRegistrada(ubicacion: ubicacion, espacio: espacio));
    } on UbicacionDuplicadaException catch (e) {
      _log.info(LogModulo.db, 'UBICACION_DUPLICADA', 'alta frenada por posibles duplicados', {
        'ubicacion_id': ubicacion.id,
        'candidatas': [for (final c in e.candidatas) c.id],
      });
      return Right(AltaConDuplicados(candidatas: [for (final c in e.candidatas) c.toEntity()]));
    } on Object catch (e, st) {
      _log.error(
        LogModulo.db,
        'UBICACION_ALTA_FAIL',
        'no se pudo guardar la ubicación',
        {'ubicacion_id': ubicacion.id},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Stream<List<Ubicacion>> observarDelColportor({
    required String colportorId,
    String? ciudadId,
    bool incluirBajas = false,
  }) => _local
      .observarDelColportor(
        colportorId: colportorId,
        ciudadId: ciudadId,
        incluirBajas: incluirBajas,
      )
      .map((modelos) => [for (final m in modelos) m.toEntity()]);

  @override
  Stream<List<MarcadorMapa>> observarMarcadoresEnArea({
    required String colportorId,
    required AreaMapa area,
  }) => _local.observarMarcadoresEnArea(colportorId: colportorId, area: area);
}
