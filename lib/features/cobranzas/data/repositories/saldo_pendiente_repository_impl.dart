import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/venta_con_saldo.dart';
import '../../domain/repositories/saldo_pendiente_repository.dart';
import '../datasources/cobranza_local_data_source_drift.dart';

/// [SaldoPendienteRepository] sobre [CobranzaLocalDataSourceDrift].
///
/// Si la base no se puede leer, el `Stream` falla con [FailureSaldoNoDisponible] y no emite un 0 que
/// se lea como «no debe nada». Al log va solo el tipo de la excepción (convenciones §7.5): ni montos
/// ni ids de personas.
final class SaldoPendienteRepositoryImpl implements SaldoPendienteRepository {
  SaldoPendienteRepositoryImpl(this._local, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final CobranzaLocalDataSourceDrift _local;
  final AppLogger _log;

  @override
  Stream<VentaConSaldo?> observarVenta(String ventaId) =>
      _traducir('venta', _local.observarVentaConSaldo(ventaId));

  @override
  Stream<int> observarDePersona(String personaId) =>
      _traducir('persona', _local.observarSaldoDePersona(personaId));

  @override
  Stream<int> observarDeUbicacion(String ubicacionId) =>
      _traducir('ubicacion', _local.observarSaldoDeUbicacion(ubicacionId));

  @override
  Stream<int> observarTotal(String colportorId) =>
      _traducir('colportor', _local.observarSaldoTotal(colportorId));

  Stream<T> _traducir<T>(String corte, Stream<T> origen) =>
      origen.handleError((Object error, StackTrace st) {
        _log.warn(LogModulo.db, 'COBRO_SALDO_STREAM_FAIL', 'no se pudo calcular el saldo', {
          'corte': corte,
          'tipo': error.runtimeType.toString(),
        });
        throw const FailureSaldoNoDisponible();
      });
}

/// Sin DB abierta no hay de dónde calcular: todo `Stream` falla con [FailureSaldoNoDisponible].
final class SaldoPendienteSinBase implements SaldoPendienteRepository {
  const SaldoPendienteSinBase();

  @override
  Stream<VentaConSaldo?> observarVenta(String ventaId) => _falla();

  @override
  Stream<int> observarDePersona(String personaId) => _falla();

  @override
  Stream<int> observarDeUbicacion(String ubicacionId) => _falla();

  @override
  Stream<int> observarTotal(String colportorId) => _falla();

  Stream<T> _falla<T>() => Stream<T>.error(const FailureSaldoNoDisponible());
}
