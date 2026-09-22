import 'dart:async';
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
/// [abrir], [cerrar] y [borrar] **no se solapan**: cada una espera a la que esté en curso (ver
/// `_enExclusiva`). Sin eso las guardas de estado serían check-then-act —`_db` se asigna varios
/// `await` después de mirarlo— y dos aperturas simultáneas dejarían una DB colgada con su clave
/// viva, o un cierre disparado durante una apertura se iría sin cerrar nada.
///
/// **Límite conocido de la clave en memoria**: para el `PRAGMA key` la clave se convierte a hex y
/// ese `String` es inmutable, así que [ClaveDb.destruir] no lo puede pisar; queda en el heap del
/// isolate de la DB hasta que pase el GC. Es inherente a pasar la clave por `package:sqlite3` (el
/// pragma no acepta parámetros preparados) y no hay forma de evitarlo sin cambiar de mecanismo de
/// apertura. Lo que sí se controla es que ese hex no salga del proceso: nunca va a un log
/// (ver `_sinClave`) ni a un mensaje de excepción.
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
/// [DbLocalException] para el resto (I/O, sin espacio, esquema del archivo posterior al de la app),
/// en las tres operaciones. Los `Error` (`StateError`, `UnsupportedError`) son bugs de programa o
/// de build, no fallas del dispositivo: se dejan pasar tal cual, pero se loguean.
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

  /// Operación en curso ([abrir], [cerrar] o [borrar]), o `null` si no hay ninguna. Nunca completa
  /// con error: es el turno, no el resultado.
  Future<void>? _enCurso;

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
  /// Antes de devolver verifica que la DB responde; que el archivo no venga de una versión
  /// posterior del esquema se comprueba en el `setup`, antes de que Drift lo migre.
  ///
  /// Si hay otra operación en curso, espera a que termine antes de empezar (ver § Ciclo de vida).
  ///
  /// Lanza [ClaveDbIncorrectaException] si SQLCipher no puede leer el archivo con esa clave
  /// (`file is not a database`: clave distinta, archivo sin cifrar o corrupto), [DbLocalException]
  /// ante cualquier otra falla, `StateError` si ya hay una DB abierta o la clave ya fue destruida,
  /// y `UnsupportedError` si el binario de SQLite del build no es SQLCipher. En todo fallo la
  /// clave queda destruida y el helper cerrado; el archivo **no** se toca.
  Future<AppDatabase> abrir(ClaveDb clave) => _enExclusiva(() => _abrir(clave));

  Future<AppDatabase> _abrir(ClaveDb clave) async {
    if (abierta) {
      throw StateError('la DB local ya está abierta: cerrar() antes de abrir con otra clave');
    }
    // Se extrae acá (y no dentro de `setup`) para que una clave destruida falle rápido con el
    // StateError de ClaveDb, y para que al isolate viaje solo el hex y no el objeto.
    final hex = _aHex(clave.bytes);

    AppDatabase? db;
    var tomada = false;
    try {
      final archivoDb = await archivo();
      final existia = await archivoDb.exists();
      db = AppDatabase(
        driftDatabase(
          name: p.basenameWithoutExtension(_nombreArchivo),
          native: DriftNativeOptions(
            databasePath: () async => archivoDb.path,
            tempDirectoryPath: () async => (await _directorioTemporal()).path,
            setup: _setupCifrado(hex, AppDatabase.versionEsquema),
          ),
        ),
        logger: _log,
      );

      // Primera query real: es la que dispara la apertura del archivo en el isolate y prueba que
      // la DB responde. No se compara `user_version` acá porque para este punto Drift ya la
      // escribió durante sus migraciones y la comparación nunca podría fallar; el archivo de una
      // versión posterior lo rechaza `_setupCifrado`.
      await db.customSelect('SELECT 1').getSingle();

      _db = db;
      _clave = clave;
      tomada = true;
      _log.info(LogModulo.db, 'DB_ABIERTA', 'DB local abierta', {'nueva': !existia});
      return db;
    } on Object catch (e, stack) {
      await _cerrarIntentoFallido(db);
      _fallar(e, stack);
    } finally {
      // En `finally` y no en el `catch`: si el que falla es el propio opener de Drift (por ejemplo
      // el directorio temporal), `close()` relanza esa falla, y destruir la clave ahí adentro se
      // saltearía. La clave no puede sobrevivir a un intento fallido (HU-AUTH-009).
      if (!tomada) clave.destruir();
    }
  }

  /// Cierra la DB y destruye la clave (HU-AUTH-006: la clave vive solo mientras la sesión está
  /// activa). Si no hay nada abierto, no hace nada. Si hay una apertura en curso, espera a que
  /// termine y cierra lo que haya quedado abierto.
  ///
  /// La clave se destruye aunque el cierre falle; si falla, lanza [DbLocalException] (operación
  /// `cerrar`) y el helper queda igual cerrado.
  Future<void> cerrar() => _enExclusiva(_cerrar);

  Future<void> _cerrar() async {
    final db = _db;
    if (db == null) return;
    Object? falla;
    StackTrace? rastro;
    try {
      await db.close();
    } on Object catch (e, stack) {
      falla = e;
      rastro = stack;
    } finally {
      _db = null;
      _clave?.destruir();
      _clave = null;
    }

    if (falla != null) {
      _log.error(
        LogModulo.db,
        'CLOSE_FAIL',
        'no se pudo cerrar la DB local (la clave igual quedó destruida)',
        const {},
        falla,
        rastro,
      );
      throw DbLocalException(operacion: 'cerrar', causa: falla);
    }
    _log.info(LogModulo.db, 'DB_CERRADA', 'DB local cerrada y clave destruida');
  }

  /// Borra el archivo de la DB (y su journal/WAL si quedaron). **Destructivo**: es el borrado de
  /// datos de HU-AUTH-010 y la limpieza de una creación interrumpida (HU-AUTH-009). Si el archivo
  /// no existe, no hace nada. Lanza `StateError` si la DB está abierta (cerrar primero) y
  /// [DbLocalException] si el borrado falla.
  ///
  /// La sal y la marca del almacén seguro no son de este helper: `CustodiaClaveDb.olvidar()`.
  Future<void> borrar() => _enExclusiva(_borrar);

  Future<void> _borrar() async {
    if (abierta) {
      throw StateError('la DB local está abierta: cerrar() antes de borrar()');
    }
    var existia = false;
    try {
      final archivoDb = await archivo();
      for (final sufijo in const ['', '-journal', '-wal', '-shm']) {
        final f = File('${archivoDb.path}$sufijo');
        if (await f.exists()) {
          existia = existia || sufijo.isEmpty;
          await f.delete();
        }
      }
    } on Object catch (e, stack) {
      _log.error(
        LogModulo.db,
        'DELETE_FAIL',
        'no se pudo borrar el archivo de la DB local',
        const {},
        e,
        stack,
      );
      throw DbLocalException(operacion: 'borrar', causa: e);
    }
    _log.warn(LogModulo.db, 'DB_BORRADA', 'archivo de la DB local borrado', {'existia': existia});
  }

  /// Corre [operacion] con el helper para ella sola.
  ///
  /// Las guardas de [abrir]/[cerrar]/[borrar] miran `_db`, que recién se asigna varios `await`
  /// después: sin este turno, dos [abrir] solapadas pasarían las dos (la primera DB quedaría
  /// abierta, con su isolate vivo y su clave nunca destruida) y un [cerrar] disparado durante una
  /// apertura vería `_db == null` y se iría dejando la DB abierta después del logout.
  ///
  /// Espera en vez de rechazar: el llamador de la UI no controla el solapamiento, y esperar deja
  /// el mismo resultado que si las llamadas hubieran llegado en orden (la segunda [abrir] ve el
  /// estado ya consolidado y falla con el `StateError` de siempre, sin tocar su clave).
  Future<T> _enExclusiva<T>(Future<T> Function() operacion) async {
    // `_enCurso` se asigna antes del primer `await` de la operación, así que no hay ventana entre
    // mirar el turno y tomarlo. El `while` re-mira porque varios esperando despiertan juntos.
    while (_enCurso != null) {
      await _enCurso!;
    }
    final turno = Completer<void>();
    _enCurso = turno.future;
    try {
      return await operacion();
    } finally {
      _enCurso = null;
      turno.complete();
    }
  }

  /// Cierra la DB de un intento de apertura fallido sin dejar escapar nada: cuando el que falló es
  /// el opener, `close()` relanza esa misma falla y taparía la excepción tipada de [_fallar].
  Future<void> _cerrarIntentoFallido(AppDatabase? db) async {
    if (db == null) return;
    try {
      await db.close();
    } on Object catch (e) {
      _log.debug(LogModulo.db, 'CLOSE_FAIL', 'el intento fallido de apertura tampoco cerró', {
        'error': e.runtimeType.toString(),
      });
    }
  }

  /// Traduce la falla de [abrir]: desenvuelve la excepción remota del isolate, distingue clave
  /// incorrecta de otra falla, y deja pasar los `Error` tal cual (son bugs, no se traducen) — pero
  /// logueando, porque si no un build sin SQLCipher falla sin rastro.
  Never _fallar(Object e, StackTrace stack) {
    final remota = e is DriftRemoteException ? e : null;
    final causa = remota?.remoteCause ?? e;
    // El stack del isolate dice dónde falló de verdad; el local solo dice "await en abrir()".
    final rastro = remota?.remoteStackTrace ?? stack;

    if (causa is Error) {
      _log.error(
        LogModulo.db,
        'OPEN_FAIL',
        'no se pudo abrir la DB cifrada',
        {'motivo': 'bug_o_build'},
        causa,
        rastro,
      );
      Error.throwWithStackTrace(causa, rastro);
    }
    if (causa is SqliteException && causa.resultCode == SqlError.SQLITE_NOTADB) {
      _log.error(LogModulo.db, 'OPEN_FAIL', 'no se pudo abrir la DB cifrada', {
        'motivo': 'clave_incorrecta',
      });
      throw const ClaveDbIncorrectaException();
    }
    if (causa is DbLocalException) {
      // Ya viene tipada desde el `setup` (esquema del archivo posterior al de la app): no se
      // envuelve de nuevo, y el detalle con las dos versiones va al log.
      _log.error(
        LogModulo.db,
        'OPEN_FAIL',
        'no se pudo abrir la DB cifrada',
        {'motivo': 'esquema_incompatible'},
        causa.causa,
        rastro,
      );
      throw causa;
    }
    final detalle = _sinClave(causa);
    _log.error(
      LogModulo.db,
      'OPEN_FAIL',
      'no se pudo abrir la DB cifrada',
      {'motivo': 'otro'},
      detalle,
      rastro,
    );
    throw DbLocalException(operacion: 'abrir', causa: detalle);
  }

  /// La clave en hex viaja en el `PRAGMA key` del `setup`: si SQLCipher falla ahí, el
  /// `causingStatement` de la [SqliteException] la lleva entera y `toString()` la imprimiría en el
  /// log. En ese caso al log va solo el código y el mensaje.
  static Object _sinClave(Object causa) {
    if (causa is SqliteException && (causa.causingStatement?.contains('PRAGMA key') ?? false)) {
      return 'SqliteException(${causa.resultCode}): ${causa.message}';
    }
    return causa;
  }

  static String _aHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// `setup` de la conexión: corre en el isolate de la DB, una vez por conexión, antes de que Drift
/// toque el archivo. Es una función de nivel superior a propósito: lo único que cruza al isolate
/// es el hex de la clave y la versión esperada del esquema.
///
/// Sigue el ejemplo oficial de Drift (`examples/encryption`): verificar que el binario es el
/// cifrado, poner la clave, y comprobar que abre leyendo `sqlite_master`. Con SQLCipher la
/// verificación es `PRAGMA cipher_version` (con SQLite común devuelve vacío).
///
/// El chequeo de `user_version` va acá y no después de abrir porque Drift, al abrir, corre sus
/// migraciones y **escribe** `user_version`: mirarla después nunca detectaría nada.
void Function(CommonDatabase) _setupCifrado(String hexClave, int versionEsperada) => (db) {
  if (db.select('PRAGMA cipher_version;').isEmpty) {
    throw UnsupportedError(
      'el binario de SQLite de este build no es SQLCipher: revisar `hooks` en pubspec.yaml',
    );
  }
  // Formato crudo de SQLCipher: x'<64 hex>' = 32 bytes usados tal cual como clave AES-256.
  // El pragma no acepta parámetros preparados; el hex no necesita escape.
  db.execute('PRAGMA key = "x\'$hexClave\'";');
  db.execute('SELECT count(*) FROM sqlite_master;');

  final version = db.select('PRAGMA user_version;').first.columnAt(0) as int?;
  if (version != null && version > versionEsperada) {
    // Un archivo escrito por una versión más nueva de la app (downgrade, o un restore de backup
    // de otro dispositivo): esta versión del esquema no sabe leerlo.
    throw DbLocalException(
      operacion: 'abrir',
      causa:
          'user_version del archivo ($version) es posterior al esquema de la app '
          '($versionEsperada)',
    );
  }
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

/// Falla de la DB local que no es de clave: I/O, sin espacio, directorio inaccesible, esquema del
/// archivo posterior al de la app.
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
