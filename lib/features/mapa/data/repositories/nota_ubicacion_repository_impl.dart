import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/nota_ubicacion.dart';
import '../../domain/repositories/nota_ubicacion_repository.dart';
import '../datasources/nota_persona_local_data_source.dart' show NotaRechazadaException;
import '../datasources/nota_ubicacion_local_data_source.dart';

/// Implementación de [NotaUbicacionRepository] sobre [NotaUbicacionLocalDataSource].
///
/// - Traduce el rechazo de la persistencia (`NotaRechazadaException`) a un `FailureValidacion` y
///   cualquier otra excepción a `FailureInesperado`; nunca deja escapar una.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos: ni el texto de la nota ni la dirección
///   del lugar (convenciones §7.5).
final class NotaUbicacionRepositoryImpl implements NotaUbicacionRepository {
  NotaUbicacionRepositoryImpl(this._local, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final NotaUbicacionLocalDataSource _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, NotaUbicacion>> agregar(NotaUbicacion nota) => _correr('NOTA_LUGAR_ALTA', {
    'nota_id': nota.id,
    'ubicacion_id': nota.ubicacionId,
  }, () => _local.agregar(nota));

  @override
  Future<Either<Failure, NotaUbicacion>> editar({
    required String id,
    required String texto,
    required DateTime ahora,
  }) => _correr('NOTA_LUGAR_EDICION', {
    'nota_id': id,
  }, () => _local.editar(id: id, texto: texto, ahora: ahora));

  @override
  Future<Either<Failure, NotaUbicacion>> borrar({required String id, required DateTime ahora}) =>
      _correr('NOTA_LUGAR_BAJA', {'nota_id': id}, () => _local.borrar(id: id, ahora: ahora));

  @override
  Future<Either<Failure, NotaUbicacion>> restaurar({required String id, required DateTime ahora}) =>
      _correr('NOTA_LUGAR_RESTAURAR', {
        'nota_id': id,
      }, () => _local.restaurar(id: id, ahora: ahora));

  @override
  Stream<List<NotaUbicacion>> observar(String ubicacionId) => _local.observar(ubicacionId);

  Future<Either<Failure, NotaUbicacion>> _correr(
    String operacion,
    Map<String, Object?> contexto,
    Future<NotaUbicacion> Function() accion,
  ) async {
    try {
      return Right(await accion());
    } on NotaRechazadaException catch (e) {
      _log.info(LogModulo.db, '${operacion}_RECHAZADA', 'operación sobre una nota rechazada', {
        ...contexto,
        'motivo': e.motivo.name,
      });
      return Left(FailureValidacion(campos: {e.motivo.campo: e.motivo.mensaje}));
    } on Object catch (e, st) {
      // Ni al log ni a la falla va la excepción tal cual: la de Drift trae la sentencia con sus
      // parámetros, que acá son el texto de la nota (convenciones §7.5). Solo su tipo.
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        '${operacion}_FAIL',
        'falló una operación sobre una nota',
        {...contexto, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailureInesperado(causa: tipo));
    }
  }
}
