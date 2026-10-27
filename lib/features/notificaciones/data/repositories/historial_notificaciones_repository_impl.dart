import 'dart:async';

import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/notificacion.dart';
import '../../domain/entities/tipo_notificacion.dart';
import '../../domain/repositories/historial_notificaciones_repository.dart';
import '../datasources/historial_notificaciones_local_data_source_drift.dart';

/// [HistorialNotificacionesRepository] sobre la DB local.
///
/// Ninguna operación lanza: una falla de la base se vuelve `FailureInesperado` y al log va solo su
/// tipo (la excepción de Drift trae la sentencia con sus parámetros, y el texto de un aviso puede
/// traer una dirección: convenciones §7.5). Los flujos que fallan terminan en error y la pantalla
/// ofrece «Reintentar».
final class HistorialNotificacionesRepositoryImpl implements HistorialNotificacionesRepository {
  HistorialNotificacionesRepositoryImpl(this._local, {AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final HistorialNotificacionesLocalDataSourceDrift _local;
  final AppLogger _log;

  @override
  Future<Either<Failure, bool>> registrar(Notificacion notificacion, {required DateTime ahora}) =>
      _correr(
        'NOTIF_REGISTRAR',
        {'id': notificacion.id, 'tipo': notificacion.tipo.codigo},
        () async {
          final nueva = await _local.registrar(notificacion);
          // La purga es mantenimiento: si falla, el aviso ya quedó guardado y lo vencido no se lee.
          try {
            await _local.purgarVencidas(ahora: ahora);
          } on Object catch (e) {
            _log.warn(LogModulo.db, 'NOTIF_PURGA_FAIL', 'no se pudo purgar el historial', {
              'tipo': e.runtimeType.toString(),
            });
          }
          return nueva;
        },
      );

  @override
  Stream<List<Notificacion>> observar({TipoNotificacion? tipo, required DateTime ahora}) =>
      _conLog(_local.observar(tipo: tipo, ahora: ahora), 'NOTIF_OBSERVAR_FAIL');

  @override
  Stream<int> observarNoLeidas({required DateTime ahora}) =>
      _conLog(_local.observarNoLeidas(ahora: ahora), 'NOTIF_NO_LEIDAS_FAIL');

  @override
  Future<Either<Failure, Unit>> marcarLeida(String id, {required DateTime ahora}) =>
      _correr('NOTIF_LEER', {'id': id}, () async {
        await _local.marcarLeida(id, ahora: ahora);
        return unit;
      });

  @override
  Future<Either<Failure, Unit>> marcarTodasLeidas({required DateTime ahora}) =>
      _correr('NOTIF_LEER_TODAS', const {}, () async {
        await _local.marcarTodasLeidas(ahora: ahora);
        return unit;
      });

  @override
  Future<Either<Failure, int>> borrarTodas({DateTime? hasta}) =>
      _correr('NOTIF_BORRAR_TODAS', const {}, () => _local.borrarTodas(hasta: hasta));

  @override
  Future<Either<Failure, int>> purgarVencidas({required DateTime ahora}) =>
      _correr('NOTIF_PURGAR', const {}, () => _local.purgarVencidas(ahora: ahora));

  /// Deja una línea en el log, sin el texto de ningún aviso, y sigue con el error: la pantalla lo
  /// ve como el error del flujo.
  Stream<T> _conLog<T>(Stream<T> flujo, String evento) => flujo.transform(
    StreamTransformer<T, T>.fromHandlers(
      handleData: (dato, sink) => sink.add(dato),
      handleError: (error, st, sink) {
        _log.error(
          LogModulo.db,
          evento,
          'falló la lectura del historial de avisos',
          {'tipo': error.runtimeType.toString()},
          null,
          st,
        );
        sink.addError(error, st);
      },
    ),
  );

  Future<Either<Failure, T>> _correr<T>(
    String evento,
    Map<String, Object?> contexto,
    Future<T> Function() operacion,
  ) async {
    try {
      return Right(await operacion());
    } on Object catch (e, st) {
      final tipo = e.runtimeType.toString();
      _log.error(
        LogModulo.db,
        '${evento}_FAIL',
        'falló una operación del historial de avisos',
        {...contexto, 'tipo': tipo},
        null,
        st,
      );
      return Left(FailureInesperado(causa: tipo));
    }
  }
}
