import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/nueva_venta.dart';
import '../../domain/entities/venta.dart';
import '../../domain/entities/venta_item.dart';
import '../../domain/repositories/venta_repository.dart';
import '../datasources/venta_local_data_source_drift.dart';

/// Implementación de [VentaRepository] sobre [VentaLocalDataSourceDrift].
///
/// - Traduce el rechazo de la persistencia a su `Failure` (talonario repetido, persona ausente) y
///   cualquier otra excepción a [FailureVentaNoGuardada]; nunca deja escapar una.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos: ni el talonario, ni el motivo del
///   monto, ni nada de la persona (convenciones §7.5).
final class VentaRepositoryImpl implements VentaRepository {
  VentaRepositoryImpl(this._local, {AppLogger? logger}) : _log = logger ?? AppLogger.instance;

  final VentaLocalDataSourceDrift _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, VentaGuardada>> registrar(
    Venta venta,
    List<VentaItem> items, {
    int? diferenciaCentavos,
    AntesDeGuardarLaVenta? antesDeGuardar,
  }) => _correr(
    'VENTA_ALTA',
    {'venta_id': venta.id},
    () => _local.registrar(
      venta,
      items,
      diferenciaCentavos: diferenciaCentavos,
      antesDeGuardar: antesDeGuardar,
    ),
  );

  @override
  Future<Either<Failure, VentaDelTalonario?>> talonarioUsado({
    required String colportorId,
    required String numero,
    required DateTime fecha,
  }) => _correr('VENTA_TALONARIO', {
    'colportor_id': colportorId,
  }, () => _local.talonarioUsado(colportorId: colportorId, numero: numero, fecha: fecha));

  Future<Either<Failure, T>> _correr<T>(
    String evento,
    Map<String, Object?> contexto,
    Future<T> Function() operacion,
  ) async {
    try {
      return Right(await operacion());
    } on TalonarioRepetidoException catch (e) {
      _log.info(LogModulo.db, '${evento}_RECHAZADA', 'talonario repetido', {
        ...contexto,
        'motivo': 'talonario_repetido',
      });
      return Left(FailureTalonarioRepetido(numero: e.numero, ventaDel: e.ventaDel));
    } on VentaSinPersonaException {
      _log.info(LogModulo.db, '${evento}_RECHAZADA', 'persona ausente', {
        ...contexto,
        'motivo': 'persona',
      });
      return const Left(
        FailureValidacion(
          campos: {'persona': 'La persona de esta venta ya no está en tu teléfono.'},
        ),
      );
    } on Object catch (e, st) {
      // Ni al log ni a la falla va la excepción tal cual: la de Drift trae la sentencia con sus
      // parámetros (el talonario, el motivo). Solo su tipo (convenciones §7.5).
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        '${evento}_FAIL',
        'falló una operación de venta',
        {...contexto, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailureVentaNoGuardada(causa: tipo));
    }
  }
}
