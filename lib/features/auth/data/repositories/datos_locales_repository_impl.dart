import 'package:dartz/dartz.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/secure_storage/custodia_clave_db.dart';
import '../../domain/entities/resumen_datos_locales.dart';
import '../../domain/repositories/datos_locales_repository.dart';
import '../datasources/auth_remote_data_source.dart';
import '../datasources/backup_drive_data_source.dart';

/// Implementación de [DatosLocalesRepository] sobre la DB cifrada ([DatabaseHelper]; la abierta y
/// su cierre llegan como funciones, desde `dbLocalProvider`), la custodia de su clave
/// ([CustodiaClaveDb]) y el backup en Drive ([BackupDriveDataSource]).
///
/// ## Qué se cuenta hoy
///
/// - **Operaciones sin sincronizar**: todavía no hay motor de sync ni `sync_queue` (ADR-007), así
///   que **nada** de lo local se subió nunca: cada fila de negocio cuenta como pendiente. Hoy la
///   única tabla de negocio es `jornada` (HU-JOR-001). Cuando exista `sync_queue`, el conteo pasa a
///   ser el de esa tabla.
/// - **Personas y visitas**: sus tablas todavía no existen (HU-UBI, HU-VIS), así que no puede haber
///   ninguna en el teléfono.
///
/// Sin el archivo de la DB no hay nada que perder (cero de todo). Con el archivo pero sin la DB
/// abierta no se puede contar: el conteo llega como `null` y el borrado igual se puede hacer
/// (decisión de Cristian en #66), avisando que no se sabe cuánto se pierde.
final class DatosLocalesRepositoryImpl implements DatosLocalesRepository {
  DatosLocalesRepositoryImpl(
    this._helper,
    this._dbAbierta,
    this._cerrarDb,
    this._custodia,
    this._backupDrive, {
    AppLogger? logger,
  }) : _log = logger ?? AppLogger.instance;

  final DatabaseHelper _helper;
  final AppDatabase? Function() _dbAbierta;
  final Future<void> Function() _cerrarDb;
  final CustodiaClaveDb _custodia;
  final BackupDriveDataSource _backupDrive;
  final AppLogger _log;

  @override
  Future<Either<Failure, ResumenDatosLocales>> resumen() async {
    try {
      return Right(
        ResumenDatosLocales(
          personas: 0,
          visitas: 0,
          operacionesSinSincronizar: await _contarSinSincronizar(),
          hayBackupEnDrive: await _hayBackup(),
        ),
      );
    } on Object catch (e, st) {
      _log.error(LogModulo.db, 'RESUMEN_LOCAL_FAIL', 'no se pudo contar lo local', const {}, e, st);
      return const Left(FailureDatosLocalesIlegibles());
    }
  }

  @override
  Future<Either<Failure, ResultadoBorradoDatosLocales>> borrar({
    required bool incluirBackupDrive,
  }) async {
    // Lo que se pierde, solo para el log: la pantalla ya lo avisó y el usuario lo confirmó.
    final pendientes = await _contarSinSincronizar();

    // 1. Lo local. Cada paso tolera que lo suyo ya no esté, así que reintentar tras una falla a
    // mitad termina el trabajo: sin DB abierta `cerrar` no hace nada, sin archivo `borrar` tampoco,
    // y no hay ninguna guarda que un intento a medias pueda dejar trabada.
    try {
      await _cerrarDb();
      await _helper.borrar();
      await _custodia.olvidarDatosDelUsuario();
      // Caché de tiles del mapa: llega con el mapa (Sprint 5, ADR-011); hoy no existe.
    } on Object catch (e, st) {
      _log.error(LogModulo.db, 'WIPE_FAIL', 'el borrado local falló', const {}, e, st);
      return Left(FailureInesperado(causa: e));
    }

    // 2. Drive, si se pidió. Su falla no revierte lo local (HU-AUTH-010).
    var resultado = ResultadoBorradoDatosLocales.completo;
    if (incluirBackupDrive) {
      try {
        await _backupDrive.borrar();
      } on SinConexionException {
        resultado = ResultadoBorradoDatosLocales.backupDriveNoBorradoSinConexion;
        _log.warn(LogModulo.backup, 'WIPE_DRIVE_OFFLINE', 'no se pudo borrar el backup: sin red');
      } on Object catch (e, st) {
        resultado = ResultadoBorradoDatosLocales.backupDriveNoBorrado;
        _log.error(
          LogModulo.backup,
          'WIPE_DRIVE_FAIL',
          'no se pudo borrar el backup',
          const {},
          e,
          st,
        );
      }
    }

    // `audit_log` todavía no existe en la DB (y la DB se acaba de borrar): el evento queda en el
    // log con los campos de la HU salvo `device_id`, que la app todavía no tiene.
    _log.info(LogModulo.db, 'local_data_wipe', 'datos locales borrados', {
      'included_drive_backup': incluirBackupDrive,
      'drive_ok': resultado == ResultadoBorradoDatosLocales.completo,
      'pendientes_descartados': pendientes,
    });
    return Right(resultado);
  }

  /// `null` si no se puede saber: el archivo está pero la DB no está abierta, o contar falló.
  Future<int?> _contarSinSincronizar() async {
    try {
      final db = _dbAbierta();
      if (db == null) return await _helper.existe() ? null : 0;
      final fila = await db.customSelect('SELECT COUNT(*) AS n FROM jornada').getSingle();
      return fila.read<int>('n');
    } on Object catch (e, st) {
      _log.error(
        LogModulo.db,
        'CONTEO_LOCAL_FAIL',
        'no se pudo contar lo pendiente',
        const {},
        e,
        st,
      );
      return null;
    }
  }

  /// Si Drive no responde, se trata como que no hay backup: la opción de incluirlo no aparece y el
  /// borrado local sigue siendo posible. Lo único que se pierde es ofrecer borrar el backup, y el
  /// usuario no puede hacer nada con eso: solo va al log.
  Future<bool> _hayBackup() async {
    try {
      return await _backupDrive.existe();
    } on Object catch (e, st) {
      _log.error(
        LogModulo.db,
        'BACKUP_DRIVE_FAIL',
        'no se pudo consultar el backup',
        const {},
        e,
        st,
      );
      return false;
    }
  }
}
