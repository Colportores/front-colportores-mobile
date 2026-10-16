// Borrado de datos locales (HU-AUTH-010) y conteo de lo que se perdería. Con SQLCipher real en un
// directorio temporal, como el resto de los tests de la DB.
import 'dart:io';
import 'dart:typed_data';

import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_helper.dart';
import 'package:colportores_mobile/core/secure_storage/archivo_envoltorio_dek.dart';
import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/cripto_sodium.dart';
import 'package:colportores_mobile/core/secure_storage/custodia_clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/envoltorio_dek.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/backup_drive_data_source.dart';
import 'package:colportores_mobile/features/auth/data/repositories/datos_locales_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/proveedor_clave_db_falso.dart';

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
  late DatosLocalesRepositoryImpl repo;
  AppDatabase? db;
  var cierreFalla = true;

  setUp(() async {
    directorio = await Directory.systemTemp.createTemp('colportores_qa_wipe_test');
    helper = DatabaseHelper(
      directorio: () async => directorio,
      directorioTemporal: () async => directorio,
      logger: loggerMudo(),
    );
    final custodia = CustodiaClaveDb(
      AlmacenSeguroEnMemoria(),
      ArchivoEnvoltorioDek(directorio: () async => directorio),
      ProveedorClaveDbFalso(),
      CriptoSodium(),
      parametros: const ParametrosArgon2id(memoriaBytes: 64 * 1024, iteraciones: 1, paralelismo: 1),
      logger: loggerMudo(),
    );
    db = null;
    cierreFalla = true;
    repo = DatosLocalesRepositoryImpl(
      helper,
      () => db,
      () async {
        if (cierreFalla) throw Exception('no se pudo cerrar la DB');
        await helper.cerrar();
        db = null;
      },
      custodia,
      _DriveFake(),
      logger: loggerMudo(),
    );
  });

  tearDown(() async {
    await helper.cerrar();
    await directorio.delete(recursive: true);
  });

  // QA #228 (menor 1 de la re-revision): si el borrado fallo porque cerrar la DB lanzo, la DB sigue
  // abierta y escribible; el colportor vuelve, carga una jornada y reintenta. El reintento no puede
  // borrar trabajo sin subir: solo deberia saltear el conteo si la DB ya esta cerrada.
  test('dado que el cierre de la DB fallo y se cargo una jornada nueva, cuando se reintenta el '
      'borrado con la DB abierta, entonces no borra el trabajo sin subir', () async {
    db = await helper.abrir(ClaveDb(Uint8List.fromList(List<int>.filled(32, 7))));
    final primero = await repo.borrar(incluirBackupDrive: false);
    expect(primero.isLeft(), isTrue, reason: 'el cierre lanzo: el borrado falla a mitad');

    await db!.customStatement(
      'INSERT INTO jornada (id, colportor_id, inicio, created_at, updated_at) '
      "VALUES ('nueva', 'c1', 0, 0, 0)",
    );
    cierreFalla = false;
    final reintento = await repo.borrar(incluirBackupDrive: false, reintento: true);

    expect(reintento.isLeft(), isTrue, reason: 'habia 1 jornada sin subir: no se borra');
    expect(await helper.existe(), isTrue, reason: 'el archivo de la DB sigue ahi');
  });
}
