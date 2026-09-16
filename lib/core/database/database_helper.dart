import 'dart:io';

import 'package:drift/isolate.dart' show DriftRemoteException;
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/common.dart' show CommonDatabase, SqlError, SqliteException;

import '../logging/app_logger.dart';
import '../secure_storage/clave_db.dart';
import 'app_database.dart';

/// Abre y cierra la DB local cifrada con SQLCipher (ADR-003, R-PV-03).
///
/// Es el **único** archivo del proyecto que sabe que la DB está cifrada: arma la conexión Drift
/// con `PRAGMA key` y entrega un [AppDatabase] listo; nadie más ve la clave. Sigue la doc oficial
/// de Drift para DBs cifradas (`driftDatabase` de `drift_flutter` + `setup` con el `PRAGMA key`),
/// con SQLCipher empaquetado por `package:sqlite3` (`hooks` en `pubspec.yaml`).
///
/// ## Qué recibe y qué no
///
/// Recibe la [ClaveDb] **ya derivada**. La derivación (Argon2id desde la contraseña + la sal de
/// `CustodiaClaveDb`) no es de este helper: llega con HU-AUTH-009 (#27) detrás de
/// `ProveedorClaveDb`, donde también se cierra el Supuesto S11. Acá la clave se usa en formato
/// crudo de SQLCipher (`x'…'`, 32 bytes = AES-256): SQLCipher no vuelve a derivar nada, porque
/// [ClaveDb] ya **es** la clave, no una contraseña.
///
/// ## Ciclo de vida
///
/// Una sesión = una DB abierta. [abrir] con la clave del login, [cerrar] al cerrar sesión. Desde
/// [abrir] el helper es dueño de la clave: la destruye en [cerrar] y también si [abrir] falla
/// (la clave no sobrevive a un intento fallido; el siguiente login la vuelve a derivar —
/// HU-AUTH-009, "segundo intento parte desde cero"). Ver `DbLocalNotifier` para el cableado
/// Riverpod.
///
/// ## Lo que el flujo de HU-AUTH-009 tiene que hacer con esto
///
/// `CustodiaClaveDb.dbInicializada()` es una marca del almacén seguro, no la existencia del archivo,
/// y en iOS se desincronizan (el Keychain sobrevive a la desinstalación). Quien orqueste el primer
/// login reconcilia con [existe]: marca puesta sin archivo → `custodia.olvidar()` y dispositivo
/// nuevo; archivo sin sal → [borrar] y dispositivo nuevo; creación interrumpida → [borrar] +
/// `olvidar()`. Este helper da las primitivas ([existe], [abrir], [cerrar], [borrar]); la
/// orquestación es de #27.
///
/// ## Errores
///
/// Como el resto de infra (§8.3), **lanza excepciones tipadas** y es el consumidor quien traduce a
/// `Failure`: [ClaveDbIncorrectaException] si la clave no abre lo que hay en disco y
/// [DbLocalException] para el resto (I/O, sin espacio). Los `Error` (`StateError`,
/// `UnsupportedError`) son bugs de programa o de build, no fallas del dispositivo.
final class DatabaseHelper {
  DatabaseHelper({
    required this._directorio,
    required this._directorioTemporal,
    this._nombreArchivo = nombreArchivoPorDefecto,
    AppLogger? logger,
  }) : _log = logger ?? AppLogger.instance;

  /// Nombre del archivo SQLCipher dentro de [directorio]. La doc del proyecto no fija nombre ni
  /// ruta; en `main.dart` el directorio es `getApplicationDocumentsDirectory()` (el default de
  /// `drift_flutter`).
  static const String nombreArchivoPorDefecto = 'colportores.sqlite';

  final Future<Directory> Function() _directorio;
  final Future<Directory> Function() _directorioTemporal;
  final String _nombreArchivo;
  final AppLogger _log;

  AppDatabase? _db;
  ClaveDb? _clave;

  /// Si hay una DB abierta ahora mismo.
  bool get abierta => _db != null;

  /// La DB abierta. Lanza `StateError` si no hay ninguna: los consumidores deben pasar por
  /// `dbLocalProvider`, que solo la expone después de [abrir].
  AppDatabase get db {
    final db = _db;
    if (db == null) {
      throw StateError('la DB local no está abierta: primero DatabaseHelper.abrir(clave)');
    }
    return db;
  }

  /// Archivo SQLCipher en disco (exista o no).
  Future<File> archivo() async => File(p.join((await _directorio()).path, _nombreArchivo));

  /// Si el archivo de la DB existe en este dispositivo. No dice nada de si la clave lo abre.
  Future<bool> existe() async => (await archivo()).exists();

  /// Abre la DB con [clave] y devuelve el [AppDatabase]. Si el archivo no existe lo crea cifrado
  /// y aplica el esquema inicial; si existe, la clave tiene que ser la misma con la que se creó.
  ///
  /// Corre en un isolate de fondo (`driftDatabase`), así que la UI no se bloquea con las queries.
  /// Antes de devolver verifica que la DB responde y que `PRAGMA user_version` es
  /// [AppDatabase.schemaVersion] (HU-AUTH-009, paso 6).
  ///
  /// Lanza [ClaveDbIncorrectaException] si SQLCipher no puede leer el archivo con esa clave
  /// (`file is not a database`: clave distinta, archivo sin cifrar o corrupto), [DbLocalException]
  /// ante cualquier otra falla, `StateError` si ya hay una DB abierta o la clave ya fue destruida,
  /// y `UnsupportedError` si el binario de SQLite del build no es SQLCipher. En todo fallo la
  /// clave queda destruida y el helper cerrado; el archivo **no** se toca.
  Future<AppDatabase> abrir(ClaveDb clave) async {
    if (abierta) {
      throw StateError('la DB local ya está abierta: cerrar() antes de abrir con otra clave');
    }
    // Se extrae acá (y no dentro de `setup`) para que una clave destruida falle rápido con el
    // StateError de ClaveDb, y para que al isolate viaje solo el hex y no el objeto.
    final hex = _aHex(clave.bytes);

    AppDatabase? db;
    try {
      final archivoDb = await archivo();
      final existia = await archivoDb.exists();
      db = AppDatabase(
        driftDatabase(
          name: p.basenameWithoutExtension(_nombreArchivo),
          native: DriftNativeOptions(
            databasePath: () async => archivoDb.path,
            tempDirectoryPath: () async => (await _directorioTemporal()).path,
            setup: _setupCifrado(hex),
          ),
        ),
        logger: _log,
      );

      final fila = await db.customSelect('PRAGMA user_version').getSingle();
      final version = fila.read<int>('user_version');
      if (version != db.schemaVersion) {
        throw StateError('user_version es $version y el esquema es ${db.schemaVersion}');
      }

      _db = db;
      _clave = clave;
      _log.info(LogModulo.db, 'DB_ABIERTA', 'DB local abierta', {'nueva': !existia});
      return db;
    } on Object catch (e, stack) {
      await db?.close();
      clave.destruir();
      _fallar(e, stack);
    }
  }

  /// Cierra la DB y destruye la clave (HU-AUTH-006: la clave vive solo mientras la sesión está
  /// activa). Si no hay nada abierto, no hace nada. La clave se destruye aunque el cierre falle.
  Future<void> cerrar() async {
    final db = _db;
    if (db == null) return;
    try {
      await db.close();
    } finally {
      _db = null;
      _clave?.destruir();
      _clave = null;
      _log.info(LogModulo.db, 'DB_CERRADA', 'DB local cerrada y clave destruida');
    }
  }

  /// Borra el archivo de la DB (y su journal/WAL si quedaron). **Destructivo**: es el borrado de
  /// datos de HU-AUTH-010 y la limpieza de una creación interrumpida (HU-AUTH-009). Si el archivo
  /// no existe, no hace nada. Lanza `StateError` si la DB está abierta: cerrar primero.
  ///
  /// La sal y la marca del almacén seguro no son de este helper: `CustodiaClaveDb.olvidar()`.
  Future<void> borrar() async {
    if (abierta) {
      throw StateError('la DB local está abierta: cerrar() antes de borrar()');
    }
    final archivoDb = await archivo();
    var existia = false;
    for (final sufijo in const ['', '-journal', '-wal', '-shm']) {
      final f = File('${archivoDb.path}$sufijo');
      if (await f.exists()) {
        existia = existia || sufijo.isEmpty;
        await f.delete();
      }
    }
    _log.warn(LogModulo.db, 'DB_BORRADA', 'archivo de la DB local borrado', {'existia': existia});
  }

  /// Traduce la falla de [abrir]: desenvuelve la excepción remota del isolate, distingue clave
  /// incorrecta de otra falla, y deja pasar los `Error` tal cual (son bugs, no se traducen).
  Never _fallar(Object e, StackTrace stack) {
    final causa = e is DriftRemoteException ? e.remoteCause : e;
    if (causa is Error) Error.throwWithStackTrace(causa, stack);

    if (causa is SqliteException && causa.resultCode == SqlError.SQLITE_NOTADB) {
      _log.error(LogModulo.db, 'OPEN_FAIL', 'no se pudo abrir la DB cifrada', {
        'motivo': 'clave_incorrecta',
      });
      throw const ClaveDbIncorrectaException();
    }
    _log.error(
      LogModulo.db,
      'OPEN_FAIL',
      'no se pudo abrir la DB cifrada',
      {'motivo': 'otro'},
      causa,
      stack,
    );
    throw DbLocalException(operacion: 'abrir', causa: causa);
  }

  static String _aHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// `setup` de la conexión: corre en el isolate de la DB, una vez por conexión, antes de que Drift
/// toque el archivo. Es una función de nivel superior a propósito: lo único que cruza al isolate
/// es el hex de la clave.
///
/// Sigue el ejemplo oficial de Drift (`examples/encryption`): verificar que el binario es el
/// cifrado, poner la clave, y comprobar que abre leyendo `sqlite_master`. Con SQLCipher la
/// verificación es `PRAGMA cipher_version` (con SQLite común devuelve vacío).
void Function(CommonDatabase) _setupCifrado(String hexClave) => (db) {
  if (db.select('PRAGMA cipher_version;').isEmpty) {
    throw UnsupportedError(
      'el binario de SQLite de este build no es SQLCipher: revisar `hooks` en pubspec.yaml',
    );
  }
  // Formato crudo de SQLCipher: x'<64 hex>' = 32 bytes usados tal cual como clave AES-256.
  // El pragma no acepta parámetros preparados; el hex no necesita escape.
  db.execute('PRAGMA key = "x\'$hexClave\'";');
  db.execute('SELECT count(*) FROM sqlite_master;');
};

/// La clave no abre el archivo que hay en disco: SQLCipher respondió `file is not a database`.
///
/// Pasa con una clave distinta a la de creación, con un archivo sin cifrar o corrupto. Para
/// HU-AUTH-009 significa "la sal de este dispositivo no corresponde a esta DB" (o la contraseña
/// no es la de este equipo). Nunca lleva la clave ni la ruta.
final class ClaveDbIncorrectaException implements Exception {
  const ClaveDbIncorrectaException();

  @override
  String toString() => 'ClaveDbIncorrectaException(file is not a database)';
}

/// Falla de la DB local que no es de clave: I/O, sin espacio, directorio inaccesible.
///
/// [toString] lleva la operación y nunca la clave.
final class DbLocalException implements Exception {
  const DbLocalException({required this.operacion, this.causa});

  /// Operación que falló: `abrir`, `cerrar`, `borrar`.
  final String operacion;

  /// Error original. Va a logs, nunca al usuario.
  final Object? causa;

  @override
  String toString() => 'DbLocalException($operacion)';
}
