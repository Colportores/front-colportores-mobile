import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/espacio.dart';
import '../../domain/entities/espacios_activos.dart';
import '../../domain/entities/marcador_mapa.dart';
import '../../domain/entities/motivo_baja.dart';
import '../../domain/entities/resultado_alta_ubicacion.dart';
import '../../domain/entities/resultado_modificacion_ubicacion.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/entities/ubicacion_con_resumen.dart';
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
        'crear_igual': duplicados?.esSeguirIgual ?? true,
      });
      return Right(AltaRegistrada(ubicacion: ubicacion, espacio: espacio));
    } on UbicacionDuplicadaException catch (e) {
      _log.info(LogModulo.db, 'UBICACION_DUPLICADA', 'alta frenada por posibles duplicados', {
        'ubicacion_id': ubicacion.id,
        'candidatas': [for (final c in e.candidatas) c.ubicacion.id],
        'motivos': [for (final c in e.candidatas) c.motivo.name],
      });
      return Right(AltaConDuplicados(candidatas: e.candidatas));
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
  Future<Either<Failure, Ubicacion?>> obtener(String id) async {
    try {
      return Right((await _local.obtener(id))?.toEntity());
    } on Object catch (e, st) {
      _log.error(
        LogModulo.db,
        'UBICACION_LEER_FAIL',
        'no se pudo leer la ubicación',
        {'ubicacion_id': id},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Future<Either<Failure, int>> contarEspaciosActivos(String ubicacionId) async {
    try {
      return Right(await _local.contarEspaciosActivos(ubicacionId));
    } on Object catch (e, st) {
      _log.error(
        LogModulo.db,
        'UBICACION_ESPACIOS_FAIL',
        'no se pudieron contar los espacios',
        {'ubicacion_id': ubicacionId},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Stream<EspaciosActivos> observarEspaciosActivos(String ubicacionId) =>
      _local.observarEspaciosActivos(ubicacionId);

  @override
  Future<Either<Failure, ResultadoModificacionUbicacion>> modificar(
    Ubicacion nueva, {
    required DateTime baseUpdatedAt,
    CriterioDuplicadoUbicacion? duplicados,
    bool reduceAUnEspacio = false,
  }) async {
    try {
      final guardada = await _local.actualizar(
        UbicacionModel.fromEntity(nueva),
        baseUpdatedAt: baseUpdatedAt,
        duplicados: duplicados,
        reduceAUnEspacio: reduceAUnEspacio,
      );
      _log.info(LogModulo.db, 'UBICACION_MODIFICADA', 'ubicación modificada', {
        'ubicacion_id': nueva.id,
        'seguir_igual': duplicados?.esSeguirIgual ?? true,
        'reduce_a_un_espacio': reduceAUnEspacio,
      });
      return Right(UbicacionModificada(ubicacion: guardada.toEntity()));
    } on UbicacionDuplicadaException catch (e) {
      _log.info(LogModulo.db, 'UBICACION_DUPLICADA', 'edición frenada por posibles duplicados', {
        'ubicacion_id': nueva.id,
        'candidatas': [for (final c in e.candidatas) c.ubicacion.id],
        'motivos': [for (final c in e.candidatas) c.motivo.name],
      });
      return Right(ModificacionConDuplicados(candidatas: e.candidatas));
    } on UbicacionConEspaciosException catch (e) {
      _log.info(
        LogModulo.db,
        'UBICACION_CON_ESPACIOS',
        'ubicación con espacios: no cambia de tipo',
        {'ubicacion_id': nueva.id, 'espacios': e.cantidad},
      );
      return Left(FailureUbicacionConEspacios(cantidadEspacios: e.cantidad));
    } on UbicacionInexistenteException {
      return const Left(FailureUbicacionInexistente());
    } on UbicacionCambioException {
      _log.info(LogModulo.db, 'UBICACION_CAMBIO_CONCURRENTE', 'la ubicación cambió al editarla', {
        'ubicacion_id': nueva.id,
      });
      return const Left(FailureUbicacionCambio());
    } on Object catch (e, st) {
      _log.error(
        LogModulo.db,
        'UBICACION_MODIFICAR_FAIL',
        'no se pudo modificar la ubicación',
        {'ubicacion_id': nueva.id},
        e,
        st,
      );
      return Left(FailureInesperado(causa: e));
    }
  }

  @override
  Future<Either<Failure, CambioDeBaja>> cambiarBaja(
    String id, {
    required bool baja,
    required DateTime baseUpdatedAt,
    required DateTime ahora,
    String? motivo,
    String? conservadaId,
  }) async {
    // El motivo es texto del colportor: a la DB (auditoría local) sí, al log solo que hubo.
    final conMotivo = baja && MotivosBaja.paraGuardar(motivo) != null;
    try {
      final (:ubicacion, :escribio) = await _local.cambiarBaja(
        id,
        baseUpdatedAt: baseUpdatedAt,
        updatedAt: ahora,
        deletedAt: baja ? ahora : null,
        motivo: baja ? MotivosBaja.paraGuardar(motivo) : null,
        conservadaId: conservadaId,
      );
      // Un solo evento de auditoría por baja (R-UB09): el segundo de dos toques no escribió.
      if (escribio) {
        _log.info(
          LogModulo.db,
          baja ? 'UBICACION_BAJA' : 'UBICACION_REACTIVADA',
          baja ? 'ubicación dada de baja' : 'ubicación reactivada',
          {'ubicacion_id': id, if (baja) 'con_motivo': conMotivo},
        );
      } else {
        _log.info(
          LogModulo.db,
          baja ? 'UBICACION_YA_DE_BAJA' : 'UBICACION_YA_ACTIVA',
          baja ? 'la ubicación ya estaba de baja' : 'la ubicación ya estaba activa',
          {'ubicacion_id': id},
        );
      }
      return Right((ubicacion: ubicacion.toEntity(), escribio: escribio));
    } on UbicacionInexistenteException {
      return const Left(FailureUbicacionInexistente());
    } on ConservadaDeBajaException {
      _log.info(
        LogModulo.db,
        'UBICACION_CONSERVADA_DE_BAJA',
        'la ubicación que se conserva ya estaba de baja',
        {'ubicacion_id': id, 'conservada_id': conservadaId},
      );
      return const Left(FailureConservadaDeBaja());
    } on UbicacionCambioException {
      _log.info(
        LogModulo.db,
        'UBICACION_CAMBIO_CONCURRENTE',
        baja ? 'la ubicación cambió antes de la baja' : 'la ubicación cambió antes de reactivarla',
        {'ubicacion_id': id},
      );
      return Left(
        baja ? const FailureBajaCambioReciente() : const FailureReactivacionCambioReciente(),
      );
    } on Object catch (e, st) {
      _log.error(
        LogModulo.db,
        'UBICACION_BAJA_FAIL',
        'no se pudo cambiar la baja',
        {'ubicacion_id': id},
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

  // Sin cache local de `house_status` (HU-VIS-005, #151): el estado no se sabe y se devuelve `null`
  // en vez de afirmar «Sin visita» para todas. Cuando exista, se lee acá junto con los espacios.
  @override
  Stream<List<UbicacionConResumen>> observarListaDelColportor({
    required String colportorId,
    bool incluirBajas = false,
  }) => _local
      .observarListaDelColportor(colportorId: colportorId, incluirBajas: incluirBajas)
      .map(
        (filas) => [
          for (final f in filas)
            UbicacionConResumen(
              ubicacion: f.ubicacion.toEntity(),
              cantidadEspacios: f.cantidadEspacios,
              motivoBaja: f.motivoBaja,
            ),
        ],
      );

  @override
  Stream<List<MarcadorMapa>> observarMarcadoresEnArea({
    required String colportorId,
    required AreaMapa area,
  }) => _local.observarMarcadoresEnArea(colportorId: colportorId, area: area);
}
