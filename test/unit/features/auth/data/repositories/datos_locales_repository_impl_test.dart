// Borrado de datos locales (HU-AUTH-010) y conteo de lo que se perdería. Con SQLCipher real en un
// directorio temporal, como el resto de los tests de la DB.
import 'dart:io';
import 'dart:typed_data';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_helper.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/custodia_clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/backup_drive_data_source.dart';
import 'package:colportores_mobile/features/auth/data/repositories/datos_locales_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/resumen_datos_locales.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';

final class _DriveFake implements BackupDriveDataSource {
  bool hay = true;
  Object? fallaAlBorrar;
  Object? fallaAlConsultar;
  int borrados = 0;

  @override
  Future<bool> existe() async {
    if (fallaAlConsultar != null) throw fallaAlConsultar!;
    return hay;
  }

  @override
  Future<void> borrar() async {
    if (fallaAlBorrar != null) throw fallaAlBorrar!;
    borrados++;
  }
}

void main() {
  late Directory directorio;
  late DatabaseHelper helper;
  late CustodiaClaveDb custodia;
  late _DriveFake drive;
  AppDatabase? db;
  late DatosLocalesRepositoryImpl repo;

  setUp(() async {
    directorio = await Directory.systemTemp.createTemp('colportores_wipe_test');
    helper = DatabaseHelper(
      directorio: () async => directorio,
      directorioTemporal: () async => directorio,
      logger: loggerMudo(),
    );
    custodia = CustodiaClaveDb(AlmacenSeguroEnMemoria(), logger: loggerMudo());
    drive = _DriveFake();
    db = null;
    repo = DatosLocalesRepositoryImpl(
      helper,
      () => db,
      () async {
        await helper.cerrar();
        db = null;
      },
      custodia,
      drive,
      logger: loggerMudo(),
    );
  });

  tearDown(() async {
    await helper.cerrar();
    await directorio.delete(recursive: true);
  });

  Future<void> abrirConJornadas(int cantidad) async {
    db = await helper.abrir(ClaveDb(Uint8List.fromList(List<int>.filled(32, 7))));
    for (var i = 0; i < cantidad; i++) {
      await db!.customStatement(
        'INSERT INTO jornada (id, colportor_id, inicio, created_at, updated_at) '
        "VALUES ('j$i', 'c1', 0, 0, 0)",
      );
    }
  }

  group('resumen', () {
    test('sin archivo de DB, no hay nada que perder', () async {
      final r = await repo.resumen();

      expect(
        r,
        const Right<Failure, ResumenDatosLocales>(
          ResumenDatosLocales(
            personas: 0,
            visitas: 0,
            operacionesSinSincronizar: 0,
            hayBackupEnDrive: true,
          ),
        ),
      );
    });

    test('con la DB abierta, cada jornada local cuenta como sin sincronizar', () async {
      await abrirConJornadas(2);

      final r = await repo.resumen();

      expect(r.getOrElse(() => throw StateError('Left')).operacionesSinSincronizar, 2);
    });

    test('con el archivo pero sin la DB abierta, el conteo llega como desconocido', () async {
      await abrirConJornadas(0);
      await helper.cerrar();
      db = null;

      final r = await repo.resumen();

      expect(r.getOrElse(() => throw StateError('Left')).operacionesSinSincronizar, isNull);
    });

    test('si Drive no responde, se muestra como sin backup', () async {
      drive.fallaAlConsultar = Exception('drive caído');

      final r = await repo.resumen();

      expect(r.getOrElse(() => throw StateError('Left')).hayBackupEnDrive, isFalse);
    });
  });

  group('borrar', () {
    test('con operaciones sin sincronizar, borra igual (decisión de #66)', () async {
      await abrirConJornadas(1);
      await custodia.generarSal();

      final r = await repo.borrar(incluirBackupDrive: false);

      expect(r.isRight(), isTrue);
      expect(helper.abierta, isFalse);
      expect(await helper.existe(), isFalse);
      expect(await custodia.leerSal(), isNull);
    });

    test('sin poder contar (archivo presente, DB cerrada), borra igual', () async {
      await abrirConJornadas(0);
      await helper.cerrar();
      db = null;

      final r = await repo.borrar(incluirBackupDrive: false);

      expect(r.isRight(), isTrue);
      expect(await helper.existe(), isFalse);
    });

    test(
      'dado un intento que falló después de cerrar la DB, reintentar termina el borrado',
      () async {
        await abrirConJornadas(2);
        await custodia.generarSal();
        var intentos = 0;
        final conFallaAMitad = DatosLocalesRepositoryImpl(
          helper,
          () => db,
          () async {
            intentos++;
            await helper.cerrar();
            db = null;
            if (intentos == 1) throw const DbLocalException(operacion: 'cerrar');
          },
          custodia,
          drive,
          logger: loggerMudo(),
        );

        final primero = await conFallaAMitad.borrar(incluirBackupDrive: false);
        expect(primero.isLeft(), isTrue);
        expect(await helper.existe(), isTrue, reason: 'quedó a mitad: DB cerrada, archivo y sal');

        final segundo = await conFallaAMitad.borrar(incluirBackupDrive: false);

        expect(segundo.isRight(), isTrue);
        expect(await helper.existe(), isFalse);
        expect(await custodia.leerSal(), isNull);
      },
    );

    test('sin pendientes, cierra y borra la DB, olvida la sal y respeta Drive', () async {
      await abrirConJornadas(0);
      await custodia.generarSal();

      final r = await repo.borrar(incluirBackupDrive: false);

      expect(
        r,
        const Right<Failure, ResultadoBorradoDatosLocales>(ResultadoBorradoDatosLocales.completo),
      );
      expect(helper.abierta, isFalse);
      expect(await helper.existe(), isFalse);
      expect(await custodia.leerSal(), isNull);
      expect(drive.borrados, 0);
    });

    test('es idempotente: reintentar sin nada que borrar no falla', () async {
      await repo.borrar(incluirBackupDrive: false);

      final r = await repo.borrar(incluirBackupDrive: false);

      expect(r.isRight(), isTrue);
    });

    test('incluyendo Drive, lo borra', () async {
      final r = await repo.borrar(incluirBackupDrive: true);

      expect(r.isRight(), isTrue);
      expect(drive.borrados, 1);
    });

    test('Drive sin red: lo local se borra igual y se informa', () async {
      drive.fallaAlBorrar = const SinConexionException();

      final r = await repo.borrar(incluirBackupDrive: true);

      expect(
        r,
        const Right<Failure, ResultadoBorradoDatosLocales>(
          ResultadoBorradoDatosLocales.backupDriveNoBorradoSinConexion,
        ),
      );
    });

    test('Drive falla por otro motivo: lo local se borra igual y se informa', () async {
      drive.fallaAlBorrar = Exception('403');

      final r = await repo.borrar(incluirBackupDrive: true);

      expect(
        r,
        const Right<Failure, ResultadoBorradoDatosLocales>(
          ResultadoBorradoDatosLocales.backupDriveNoBorrado,
        ),
      );
    });

    test('si el borrado local falla, devuelve Left', () async {
      final roto = DatosLocalesRepositoryImpl(
        helper,
        () => null,
        () async => throw const DbLocalException(operacion: 'cerrar'),
        custodia,
        drive,
        logger: loggerMudo(),
      );

      final r = await roto.borrar(incluirBackupDrive: false);

      expect(r.isLeft(), isTrue);
    });
  });

  test('BackupDriveNoDisponible no ofrece nada que borrar', () async {
    const drive = BackupDriveNoDisponible();

    expect(await drive.existe(), isFalse);
    await expectLater(drive.borrar(), completes);
  });
}
