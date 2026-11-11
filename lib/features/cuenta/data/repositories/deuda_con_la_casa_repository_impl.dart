import 'dart:convert';

import 'package:dartz/dartz.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../domain/entities/deuda_con_la_casa.dart';
import '../../domain/repositories/deuda_con_la_casa_repository.dart';
import '../datasources/deuda_con_la_casa_cache_data_source.dart';
import '../datasources/deuda_con_la_casa_remote_data_source.dart';
import '../models/deuda_con_la_casa_model.dart';

/// [DeudaConLaCasaRepository] sobre el RPC del servidor y la última respuesta guardada.
///
/// Una lectura que falla no toca lo guardado, y una respuesta que no se entiende no se guarda: lo que
/// se muestra sin conexión es siempre algo que el servidor dijo y la app entendió. Si lo guardado no
/// se puede leer (la base, o un JSON viejo que ya no se entiende) es como no tener nada. Al log va
/// solo el tipo de la falla (convenciones §7.5): ni montos ni ids.
final class DeudaConLaCasaRepositoryImpl implements DeudaConLaCasaRepository {
  DeudaConLaCasaRepositoryImpl(this._remoto, this._cache, {required this._ahora, AppLogger? logger})
    : _log = logger ?? AppLogger.instance;

  final DeudaConLaCasaRemoteDataSource _remoto;
  final DeudaConLaCasaCacheDataSource _cache;
  final DateTime Function() _ahora;
  final AppLogger _log;

  @override
  Future<LecturaDeLaDeuda?> ultimaGuardada(String colportorId) async {
    try {
      final guardada = await _cache.leer(colportorId);
      if (guardada == null) return null;
      return LecturaDeLaDeuda(
        deuda: DeudaConLaCasaModel.desdeJson(jsonDecode(guardada.respuesta)),
        leidaEn: guardada.leidaEn,
      );
    } on Object catch (e) {
      _log.warn(LogModulo.db, 'DEUDA_CASA_CACHE_LEER_FAIL', 'no se pudo leer la deuda guardada', {
        'tipo': e.runtimeType.toString(),
      });
      return null;
    }
  }

  @override
  Future<Either<Failure, LecturaDeLaDeuda>> leer(String colportorId) async {
    final Object? respuesta;
    try {
      respuesta = await _remoto.leer();
    } on DeudaSinConexionException {
      return const Left(FailureDeudaSinConexion());
    } on Object catch (e) {
      _log.warn(LogModulo.net, 'DEUDA_CASA_LEER_FAIL', 'no se pudo traer la deuda', {
        'tipo': e.runtimeType.toString(),
      });
      return const Left(FailureDeudaNoDisponible());
    }

    final DeudaConLaCasa deuda;
    try {
      deuda = DeudaConLaCasaModel.desdeJson(respuesta);
    } on Object catch (e) {
      _log.warn(LogModulo.net, 'DEUDA_CASA_RESPUESTA_FAIL', 'la respuesta no se entiende', {
        'tipo': e.runtimeType.toString(),
      });
      return const Left(FailureDeudaNoDisponible());
    }

    final leidaEn = _ahora().toUtc();
    try {
      await _cache.guardar(colportorId, jsonEncode(respuesta), leidaEn);
    } on Object catch (e) {
      // No se pudo guardar: la pantalla igual muestra lo que acaba de llegar.
      _log.warn(LogModulo.db, 'DEUDA_CASA_CACHE_GUARDAR_FAIL', 'no se pudo guardar la deuda', {
        'tipo': e.runtimeType.toString(),
      });
    }
    return Right(LecturaDeLaDeuda(deuda: deuda, leidaEn: leidaEn));
  }
}
