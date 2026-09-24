import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqlite3/common.dart' show SqlError, SqliteException;

import '../../../../core/database/database_helper.dart';
import '../../../../core/database/database_providers.dart';
import '../../../../core/dispositivo/seguridad_dispositivo.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../../../core/secure_storage/archivo_envoltorio_dek.dart';
import '../../../../core/secure_storage/clave_db.dart';
import '../../../../core/secure_storage/custodia_clave_db.dart';
import '../../../../core/secure_storage/envoltorio_dek.dart';
import '../../domain/entities/estado_db_local.dart';
import '../../domain/repositories/db_local_repository.dart';

/// [DbLocalRepository] sobre la infraestructura de la DB cifrada (ADR-006): la DEK, sus envoltorios
/// y la marca en [CustodiaClaveDb], la seguridad del equipo en [SeguridadDispositivo], el archivo en
/// [DatabaseHelper] y la apertura publicada por [DbLocalNotifier].
///
/// Como `AuthRepositoryImpl`: la infraestructura lanza excepciones tipadas y acá se traducen a
/// [Failure] (ver [traducir]). Los `Error` (bugs de programa, un provider sin implementación) no se
/// traducen: se dejan pasar.
final class DbLocalRepositoryImpl implements DbLocalRepository {
  DbLocalRepositoryImpl({
    required this._custodia,
    required this._seguridad,
    required this._helper,
    required this._dbLocal,
    AppLogger? logger,
  }) : _log = logger ?? AppLogger.instance;

  final CustodiaClaveDb _custodia;
  final SeguridadDispositivo _seguridad;
  final DatabaseHelper _helper;
  final DbLocalNotifier _dbLocal;
  final AppLogger _log;

  /// `ENOSPC` en Linux/Android y en iOS/macOS.
  static const int _errnoSinEspacio = 28;

  @override
  Future<Either<Failure, EstadoDbLocal>> estado() => _intentar('estado', () async {
    final archivoExiste = await _helper.existe();
    final envoltorioExiste = await _custodia.hayEnvoltorioPorPassword();
    return EstadoDbLocal(
      marca: await _marca(),
      archivoExiste: archivoExiste,
      envoltorioExiste: envoltorioExiste,
      abierta: _helper.abierta,
    );
  });

  /// Un almacén que falla no corta el estado: con la DB en disco eso decide la recuperación guiada.
  Future<MarcaDbLocal> _marca() async {
    try {
      return await _custodia.dbInicializada() ? MarcaDbLocal.puesta : MarcaDbLocal.ausente;
    } on Exception catch (e) {
      if (e is! AlmacenSeguroException && e is! MarcaInicializacionCorruptaException) rethrow;
      _log.error(LogModulo.db, 'MARCA_ILEGIBLE', 'no se pudo leer la marca de inicialización', {
        'error': e.runtimeType.toString(),
      });
      return MarcaDbLocal.ilegible;
    }
  }

  @override
  Future<Either<Failure, bool>> tieneBloqueoPantalla() =>
      _intentar('bloqueo_pantalla', _seguridad.tieneBloqueoPantalla);

  @override
  Future<Either<Failure, NivelAlmacenSeguro>> nivelAlmacenSeguro() =>
      _intentar('nivel_almacen', _seguridad.nivelAlmacenSeguro);

  @override
  Future<Either<Failure, Unit>> registrarConsentimientoAlmacenSoftware() =>
      _intentar('consentimiento', () async {
        await _custodia.registrarConsentimientoAlmacenSoftware();
        return unit;
      });

  @override
  Future<Either<Failure, ClaveDb?>> leerDek() => _intentar('leer_dek', _custodia.leerDek);

  @override
  Future<Either<Failure, ClaveDb>> crearDek() => _intentar('crear_dek', () async {
    final dek = _custodia.generarDek();
    try {
      await _custodia.guardarDek(dek);
    } on Object {
      dek.destruir();
      rethrow;
    }
    return dek;
  });

  @override
  Future<Either<Failure, Unit>> envolverConPassword(ClaveDb dek, String password) =>
      _intentar('envolver', () async {
        await _custodia.envolverConPassword(dek, password);
        return unit;
      });

  @override
  Future<Either<Failure, ClaveDb>> desenvolverConPassword(String password) =>
      _intentar('desenvolver', () => _custodia.desenvolverConPassword(password));

  @override
  Future<Either<Failure, Unit>> reconstruirAlmacen(ClaveDb dek) =>
      _intentar('reconstruir', () async {
        await _custodia.reconstruirAlmacen(dek);
        return unit;
      });

  /// Delega en `DbLocalNotifier.abrir` sin ningún `await` antes: el notifier registra la apertura
  /// en su primera línea sincrónica, y los casos de uso dependen de eso (ver
  /// `DbLocalRepository.abrir`).
  @override
  Future<Either<Failure, Unit>> abrir(ClaveDb dek) => _intentar('abrir', () async {
    await _dbLocal.abrir(dek);
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> marcarInicializada() => _intentar('marcar', () async {
    await _custodia.marcarDbInicializada();
    return unit;
  });

  /// Cierra (solo si hay algo abierto, para no contar un cierre de sesión que no hubo), borra el
  /// archivo y olvida la marca, la DEK y el envoltorio, en ese orden. Si se corta a mitad de
  /// camino, lo que quede sigue siendo "dispositivo nuevo" para el próximo intento: sin archivo con
  /// marca, o sin marca.
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
    } on StateError catch (e, rastro) {
      // Un estado que no debería darse (la DB ya abierta, la marca puesta al guardar otra DEK): con
      // el turno de los casos de uso no pasa, pero si pasa, se corta el flujo con un Left en vez de
      // dejarlo a medio hacer por una excepción que nadie atrapa (revisión del PR #81).
      _log.error(
        LogModulo.db,
        'INIT_DB_FAIL',
        'estado inesperado en un paso de la DB local',
        {'paso': paso},
        e,
        rastro,
      );
      return Left(FailureInesperado(causa: e));
    } on Exception catch (e) {
      final falla = traducir(e);
      // Sin la excepción ni su mensaje: las de la derivación y el cifrado no tienen por qué ir a un
      // log. El detalle de las fallas de la DB ya lo loguea DatabaseHelper, saneado.
      _log.error(LogModulo.db, 'INIT_DB_FAIL', 'falló un paso de la DB local', {
        'paso': paso,
        'codigo': falla.codigo,
        'error': e.runtimeType.toString(),
      });
      return Left(falla);
    }
  }

  /// Traduce la excepción de infraestructura al [Failure] que ve el usuario (HU-AUTH-009, ADR-006).
  @visibleForTesting
  static Failure traducir(Exception e) => switch (e) {
    AlmacenSeguroException() ||
    DekCorruptaException() ||
    MarcaInicializacionCorruptaException() ||
    SeguridadDispositivoException() ||
    // libsodium no pudo derivar o cifrar: es la preparación del almacenamiento seguro la que falla.
    CriptoException() => const FailureAlmacenSeguro(),
    EnvoltorioNoAbreException() => const FailurePasswordNoAbreDatos(),
    // Sin envoltorio que abrir (o uno que no se puede leer) no hay recuperación por contraseña.
    SinEnvoltorioException() ||
    EnvoltorioCorruptoException() => const FailureAlmacenSeguroSinRecuperacion(),
    ClaveDbIncorrectaException() => const FailureClaveDbIncorrecta(),
    // Una DB o un envoltorio de una versión más nueva de la app: se pide actualizar, nunca borrar.
    EsquemaDbPosteriorException() ||
    EnvoltorioPosteriorException() => const FailureEsquemaPosterior(),
    DbLocalException(:final causa) when _esSinEspacio(causa) => const FailureSinEspacio(),
    ArchivoEnvoltorioException(:final causa) when _esSinEspacio(causa) => const FailureSinEspacio(),
    _ => FailureInesperado(causa: e),
  };

  static bool _esSinEspacio(Object? causa) => switch (causa) {
    SqliteException(:final resultCode) => resultCode == SqlError.SQLITE_FULL,
    FileSystemException(:final osError) => osError?.errorCode == _errnoSinEspacio,
    _ => false,
  };
}
