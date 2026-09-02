// La clave con la que se cifra el backup antes de subirlo (RF-AL06, ADR-003).
//
// Vive en el Keystore del dispositivo y **no sale de ahí** (decisión 7 del plan
// de sync, 31/08/2026). Eso tiene una consecuencia que conviene tener a la
// vista al leer este archivo, porque no se ve desde el código:
//
//   Android borra las claves del Keystore cuando se desinstala la app. Si el
//   colportor desinstala, pierde el teléfono o lo cambia, esta clave se va con
//   él y **el backup que quedó en Drive no se puede volver a abrir**. Ni por
//   nosotros ni por nadie: si la clave nunca salió del dispositivo, ningún otro
//   dispositivo puede descifrar. Es aritmética, no una limitación de la
//   implementación.
//
// O sea que el backup cubre que se corrompa la base **con la app instalada**, y
// no cubre los otros tres casos. Está escrito en §11 del plan porque es lo que
// se le promete a alguien que confía su lista de contactos a la app: `persona`,
// `nota` y `espacio_persona` no se sincronizan (RD-01), así que el backup es lo
// único que los respalda.
//
// Si algún día se quiere cubrir esos casos, lo que cambia es este archivo —de
// dónde sale la clave— y no el cifrado: `AesGcmCrypto` recibe 32 bytes y no
// pregunta de dónde vienen.

import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _claveEnKeystore = 'colportaje.backup.key';

/// Los 32 bytes con los que se cifra el backup. Se generan la primera vez.
///
/// **No es la clave de SQLCipher**, y no por prolijidad: son dos cosas con
/// ciclos de vida distintos. La de la base protege un archivo que no sale del
/// dispositivo; esta protege bloques que sí salen a Drive. Reusar una sola
/// hace que rotar cualquiera de las dos —o filtrar una— arrastre a la otra.
Future<List<int>> claveDeBackup() async {
  const almacen = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final guardada = await almacen.read(key: _claveEnKeystore);
  if (guardada != null) {
    final bytes = base64Url.decode(guardada);
    if (bytes.length == 32) return bytes;
    // Una clave guardada con otro largo es de una versión anterior o está
    // corrompida. Generar una nueva encima dejaría los backups viejos
    // ilegibles **en silencio**, que es la peor forma de perderlos: mejor que
    // explote acá, donde se puede decidir qué hacer.
    throw StateError(
      'la clave de backup del Keystore no mide 32 bytes (${bytes.length}). '
      'Los backups existentes se cifraron con otra cosa: reemplazarla sin '
      'avisar los volvería ilegibles.',
    );
  }

  // 256 bits de `Random.secure()`, que en Android sale de /dev/urandom. Un
  // `Random()` común es predecible a partir de la semilla: serviría para un
  // test y no para esto.
  final azar = Random.secure();
  final nueva = List<int>.generate(32, (_) => azar.nextInt(256));
  await almacen.write(key: _claveEnKeystore, value: base64Url.encode(nueva));
  return nueva;
}
