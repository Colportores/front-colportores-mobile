import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/cobranza.dart';
import '../../domain/entities/detalle_del_cobro.dart';
import '../../domain/repositories/anulacion_de_cobro_repository.dart';
import '../datasources/cobranza_local_data_source_drift.dart';

/// Implementación de [AnulacionDeCobroRepository] sobre [CobranzaLocalDataSourceDrift].
///
/// - Traduce el rechazo de la persistencia a su `Failure` (cobro ausente, fuera de plazo) y cualquier otra
///   excepción a [FailureCobroNoAnulado]; nunca deja escapar una.
/// - Loguea en `[DB]` (convenciones §7.3) solo UUIDs y códigos: ni el monto, ni el motivo que escribió la
///   colportora, ni nada de la persona (convenciones §7.5).
final class AnulacionDeCobroRepositoryImpl implements AnulacionDeCobroRepository {
  AnulacionDeCobroRepositoryImpl(this._local, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final CobranzaLocalDataSourceDrift _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, DetalleDelCobro?>> detalle(String cobranzaId) =>
      _correr('COBRO_DETALLE', {'cobranza_id': cobranzaId}, () => _local.detalle(cobranzaId));

  @override
  Future<Either<Failure, AnulacionHecha>> anular({
    required String cobranzaId,
    required MotivoDeAnulacion motivo,
    required String colportorId,
    required DateTime ahora,
    String? justificacion,
  }) => _correr(
    'COBRO_ANULAR',
    {'cobranza_id': cobranzaId},
    () => _local.anular(
      cobranzaId: cobranzaId,
      motivo: motivo,
      colportorId: colportorId,
      ahora: ahora,
      justificacion: justificacion,
    ),
  );

  Future<Either<Failure, T>> _correr<T>(
    String evento,
    Map<String, Object?> contexto,
    Future<T> Function() operacion,
  ) async {
    try {
      return Right(await operacion());
    } on CobroAusenteException {
      _log.info(LogModulo.db, '${evento}_RECHAZADO', 'cobro ausente', {
        ...contexto,
        'motivo': 'ausente',
      });
      return const Left(FailureCobroAusente());
    } on AnulacionFueraDePlazoException {
      _log.info(LogModulo.db, '${evento}_RECHAZADO', 'pasaron las 72 h', {
        ...contexto,
        'motivo': 'fuera_de_plazo',
      });
      return const Left(FailureAnulacionFueraDePlazo());
    } on Object catch (e, st) {
      // Ni al log ni a la falla va la excepción tal cual: la de Drift trae la sentencia con sus
      // parámetros. Solo su tipo (convenciones §7.5).
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        '${evento}_FAIL',
        'falló una operación de cobro',
        {...contexto, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailureCobroNoAnulado(causa: tipo));
    }
  }
}
