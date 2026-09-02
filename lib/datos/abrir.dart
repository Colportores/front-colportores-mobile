// Abrir la DB local del dispositivo, cifrada (tarea 0.7, RD-01).
//
// El archivo de la base es el **único** lugar donde viven los datos personales
// del cliente: `persona`, `nota` y `espacio_persona` son `local` y no salen
// nunca por sync (P2). Un backup de Android, un celular perdido o un adb
// backup sobre una base en claro las expone enteras.
//
// Esto no corre en la VM: `sqlcipher_flutter_libs` trae el binario nativo. Los
// stores se prueban aparte, contra SQLite en memoria, en
// `test/drift_stores_test.dart` — por eso el esquema y la conexión viven en
// archivos distintos.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

const _claveEnKeystore = 'colportaje.db.key';

/// Abre —o crea— la base cifrada del colportor.
Future<ConexionLocal> abrirDbCifrada({String archivo = 'colportaje.db'}) async {
  // El binario de SQLCipher reemplaza al SQLite del sistema. Sin esto, el
  // `PRAGMA key` de abajo lo ignora un SQLite común y la base queda **en
  // claro**: peor que no cifrar, porque parece que sí.
  await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
  open.overrideForAll(openCipherOnAndroid);

  final dir = await getApplicationDocumentsDirectory();
  final ruta = p.join(dir.path, archivo);
  final clave = await _claveDelDispositivo();

  return ConexionLocal(
    NativeDatabase(
      File(ruta),
      setup: (db) {
        // Antes de cualquier otra sentencia: en SQLCipher el `key` tiene que ser
        // lo primero, o la base ya se abrió sin cifrar.
        db.execute("pragma key = '$clave'");

        // Que el pragma haya "funcionado" no prueba nada: sobre un SQLite común
        // `pragma key` es un no-op silencioso. Esta consulta sí falla si el
        // binario no es SQLCipher o si la clave está mal, que es exactamente lo
        // que hay que descubrir acá y no tres pantallas después.
        db.execute('select count(*) from sqlite_master');

        // WAL: con RF-SY07 hay **dos** procesos sobre este archivo —la app y el
        // isolate de segundo plano— y en el modo por defecto un lector bloquea
        // al escritor. Con WAL leen y escriben a la vez, y lo único que se
        // serializa son dos escrituras. Va después del `key` porque en
        // SQLCipher cambiar el journal necesita la base ya abierta.
        db.execute('pragma journal_mode = WAL');
      },
    ),
    ruta,
  );
}

/// La clave del dispositivo, del Keystore. Se genera la primera vez.
Future<String> _claveDelDispositivo() async {
  const almacen = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final guardada = await almacen.read(key: _claveEnKeystore);
  if (guardada != null) return guardada;

  // 256 bits de `Random.secure()`, que en Android sale de /dev/urandom. Un
  // `Random()` común es predecible a partir de la semilla y no sirve para esto.
  final azar = Random.secure();
  final clave = base64Url.encode(List<int>.generate(32, (_) => azar.nextInt(256)));
  await almacen.write(key: _claveEnKeystore, value: clave);
  return clave;
}

/// La conexión y dónde quedó el archivo, para poder mostrarlo.
class ConexionLocal {
  const ConexionLocal(this.executor, this.ruta);
  final QueryExecutor executor;
  final String ruta;
}
