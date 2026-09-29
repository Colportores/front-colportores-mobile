import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/espacio.dart';
import '../../domain/repositories/espacio_repository.dart';
import '../datasources/espacio_local_data_source.dart';
import '../models/espacio_model.dart';

/// Implementación de [EspacioRepository] sobre [EspacioLocalDataSource].
///
/// - Traduce el rechazo de la persistencia ([EspacioRechazadoException]) a un `FailureValidacion` y
///   cualquier otra excepción a `FailureInesperado`; nunca deja escapar una.
/// - Devuelve entidades de dominio, no modelos.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos: ni el número de departamento.
final class EspacioRepositoryImpl implements EspacioRepository {
  EspacioRepositoryImpl(this._local, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final EspacioLocalDataSource _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, Espacio>> agregar(Espacio espacio) => _ejecutar(
    'ESPACIO_ALTA',
    {'espacio_id': espacio.id, 'ubicacion_id': espacio.ubicacionId},
    () async {
      final insercion = await _local.insertarEspacio(EspacioModel.fromEntity(espacio));
      return insercion.espacio.toEntity();
    },
  );

  @override
  Future<Either<Failure, Espacio>> modificar(
    String id, {
    required String numeroDepto,
    required DateTime ahora,
  }) => _ejecutar('ESPACIO_MODIFICACION', {'espacio_id': id}, () async {
    final modelo = await _local.actualizarNumeroDepto(id, numeroDepto: numeroDepto, ahora: ahora);
    return modelo.toEntity();
  });

  @override
  Future<Either<Failure, Espacio>> darDeBaja(String id, {required DateTime ahora}) =>
      _ejecutar('ESPACIO_BAJA', {'espacio_id': id}, () async {
        return (await _local.darDeBajaEspacio(id, ahora: ahora)).toEntity();
      });

  @override
  Future<Either<Failure, Espacio>> restaurar(String id, {required DateTime ahora}) =>
      _ejecutar('ESPACIO_RESTAURACION', {'espacio_id': id}, () async {
        return (await _local.restaurarEspacio(id, ahora: ahora)).toEntity();
      });

  @override
  Future<Either<Failure, EspacioConUbicacion?>> buscar(String id) =>
      _ejecutar('ESPACIO_BUSQUEDA', {'espacio_id': id}, () async {
        final encontrado = await _local.buscarEspacio(id);
        if (encontrado == null) return null;
        return (espacio: encontrado.espacio.toEntity(), ubicacion: encontrado.ubicacion.toEntity());
      });

  @override
  Future<Either<Failure, List<Espacio>>> listar(String ubicacionId, {bool incluirBajas = false}) =>
      _ejecutar('ESPACIO_LISTADO', {'ubicacion_id': ubicacionId}, () async {
        final modelos = await _local.listarEspacios(ubicacionId, incluirBajas: incluirBajas);
        return [for (final modelo in modelos) modelo.toEntity()];
      });

  @override
  Future<Either<Failure, int>> contarActivos(String ubicacionId) =>
      _ejecutar('ESPACIO_CONTEO', {'ubicacion_id': ubicacionId}, () {
        return _local.contarEspaciosActivos(ubicacionId);
      });

  Future<Either<Failure, T>> _ejecutar<T>(
    String codigo,
    Map<String, Object?> contexto,
    Future<T> Function() accion,
  ) async {
    try {
      return Right(await accion());
    } on EspacioRechazadoException catch (e) {
      _log.info(LogModulo.db, '${codigo}_RECHAZADA', 'operación de espacio rechazada', {
        ...contexto,
        'motivo': e.motivo.name,
      });
      return Left(FailureValidacion(campos: {e.motivo.campo: e.motivo.mensaje}));
    } on Object catch (e, st) {
      _log.error(LogModulo.db, '${codigo}_FAIL', 'falló la operación de espacio', contexto, e, st);
      return Left(FailureInesperado(causa: e));
    }
  }
}
