import 'dart:io';
import 'dart:typed_data';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqlite3/common.dart' show SqlError, SqliteException;

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/database_providers.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../../../core/secure_storage/clave_db.dart';
import '../../../../core/secure_storage/custodia_clave_db.dart';
import '../../domain/entities/estado_db_local.dart';
import '../../domain/repositories/db_local_repository.dart';

/// [DbLocalRepository] sobre la infraestructura de la DB cifrada: la sal y la marca en
/// [CustodiaClaveDb], el archivo en [DatabaseHelper], la apertura publicada por [DbLocalNotifier]
/// y la derivación detrás de [ProveedorClaveDb] (Argon2id, pendiente — Supuesto S11).
///
/// Como `AuthRepositoryImpl`: la infraestructura lanza excepciones tipadas y acá se traducen a
/// [Failure] (ver [traducir]). Los `Error` (bugs de programa, un provider sin implementación) no se
/// traducen: se dejan pasar.
final class DbLocalRepositoryImpl implements DbLocalRepository {
  DbLocalRepositoryImpl({
    required this._custodia,
    required this._proveedorClave,
    required this._helper,
    required this._dbLocal,
    AppLogger? logger,
  }) : _log = logger ?? AppLogger.instance;

  final CustodiaClaveDb _custodia;
  final ProveedorClaveDb _proveedorClave;
  final DatabaseHelper _helper;
  final DbLocalNotifier _dbLocal;
  final AppLogger _log;

  /// `ENOSPC` en Linux/Android y en iOS/macOS.
  static const int _errnoSinEspacio = 28;

  @override
  Future<Either<Failure, EstadoDbLocal>> estado() => _intentar(
    'estado',
    () async => EstadoDbLocal(
      inicializada: await _custodia.dbInicializada(),
      archivoExiste: await _helper.existe(),
    ),
  );

  @override
  Future<Either<Failure, Uint8List?>> leerSal() => _intentar('leer_sal', _custodia.leerSal);

  @override
  Future<Either<Failure, Uint8List>> generarSal() => _intentar('generar_sal', _custodia.generarSal);

  @override
  Future<Either<Failure, ClaveDb>> derivarClave({
    required String password,
    required Uint8List sal,
  }) => _intentar('derivar_clave', () => _proveedorClave.derivar(password: password, sal: sal));

  /// Delega en `DbLocalNotifier.abrir` sin ningún `await` antes: el notifier registra la apertura
  /// en su primera línea sincrónica, y el caso de uso depende de eso (ver
  /// `DbLocalRepository.abrir`).
  @override
  Future<Either<Failure, Unit>> abrir(ClaveDb clave) => _intentar('abrir', () async {
    await _dbLocal.abrir(clave);
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> marcarInicializada() => _intentar('marcar', () async {
    await _custodia.marcarDbInicializada();
    return unit;
  });

  /// Cierra (solo si hay algo abierto, para no contar un cierre de sesión que no hubo), borra el
  /// archivo y olvida la sal y la marca, en ese orden. Si se corta a mitad de camino, lo que quede
  /// sigue siendo "dispositivo nuevo" para el próximo intento: sin archivo con marca, o sin marca.
  @override
  Future<Either<Failure, Unit>> descartar() => _intentar('descartar', () async {
    if (_helper.abierta) await _dbLocal.cerrar();
    await _helper.borrar();
    await _custodia.olvidar();
    return unit;
  });

  Future<Either<Failure, T>> _intentar<T>(String paso, Future<T> Function() accion) async {
    try {
      return Right(await accion());
    } on Exception catch (e) {
      final falla = traducir(e);
      // Sin la excepción ni su mensaje: la de la derivación viene de una implementación que todavía
      // no existe y no hay garantía de que no lleve la contraseña. El detalle de las fallas de la DB
      // ya lo loguea DatabaseHelper, saneado.
      _log.error(LogModulo.db, 'INIT_DB_FAIL', 'falló un paso de la inicialización de la DB', {
        'paso': paso,
        'codigo': falla.codigo,
        'error': e.runtimeType.toString(),
      });
      return Left(falla);
    }
  }

  /// Traduce la excepción de infraestructura al [Failure] que ve el usuario (HU-AUTH-009).
  @visibleForTesting
  static Failure traducir(Exception e) => switch (e) {
    AlmacenSeguroException() ||
    SalCorruptaException() ||
    MarcaInicializacionCorruptaException() => const FailureAlmacenSeguro(),
    ClaveDbIncorrectaException() => const FailureClaveDbIncorrecta(),
    DbLocalException(:final causa) when _esSinEspacio(causa) => const FailureSinEspacio(),
    _ => FailureInesperado(causa: e),
  };

  static bool _esSinEspacio(Object? causa) => switch (causa) {
    SqliteException(:final resultCode) => resultCode == SqlError.SQLITE_FULL,
    FileSystemException(:final osError) => osError?.errorCode == _errnoSinEspacio,
    _ => false,
  };
}
