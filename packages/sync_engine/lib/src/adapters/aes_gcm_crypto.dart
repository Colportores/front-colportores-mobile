// El que faltaba: quien cifra el backup antes de que salga del dispositivo
// (RF-AL06, ADR-003).
//
// `DriveArchive` sube, `DriftSnapshot` exporta y `CompressingCrypto` comprime y
// hashea. Lo único que no existía era el cifrado, y sin él la cadena entera
// sube en claro: el backup lleva `persona`, `nota` y `espacio_persona`, que son
// justo los datos que RD-01 y la Ley 18.331 dicen que **nunca** salen del
// dispositivo. La única red permitida para ellos es esta, cifrada.
//
// Es Dart puro y corre en la VM (§5.9). `cryptography_flutter` implementa la
// **misma** API sobre el crypto del OS: cuando entre, no cambia ni el
// algoritmo ni el formato del bloque, solo quién hace las cuentas.

import 'package:cryptography/cryptography.dart';

import 'backup_codec.dart';

/// AES-256-GCM sobre el bloque ya comprimido.
///
/// GCM y no CBC: además de cifrar, autentica. Un byte cambiado en Drive —o un
/// backup de otra cadena mezclado por error— falla al descifrar en vez de
/// devolver basura que después se intenta descomprimir y restaurar. Con CBC el
/// error aparecería recién al aplicar el payload, o peor, no aparecería.
class AesGcmCrypto extends CompressingCrypto {
  /// [clave] son los 32 bytes de la clave del usuario. De dónde salen es del
  /// que arma el adaptador —Keystore, o derivada de algo que el colportor
  /// sabe— y **no** de este archivo: ver la nota sobre RF-AL04 más abajo.
  AesGcmCrypto(List<int> clave, {super.isolateThreshold})
      : _clave = SecretKey(List<int>.unmodifiable(clave)) {
    if (clave.length != 32) {
      throw ArgumentError.value(
        clave.length,
        'clave',
        'AES-256 son 32 bytes. Una clave más corta no es "menos segura": es '
            'otro algoritmo, y encima uno que nadie revisó',
      );
    }
  }

  final SecretKey _clave;

  static final _aes = AesGcm.with256bits();

  /// 96 bits, que es el tamaño para el que GCM está definido y optimizado.
  static const _nonce = 12;

  /// 128 bits. Un tag más corto ahorra 8 bytes por backup y debilita justo lo
  /// que hace que GCM sirva.
  static const _mac = 16;

  /// El nonce lo genera la librería, uno nuevo por bloque.
  ///
  /// **Repetir un nonce con la misma clave rompe GCM entero**: no filtra solo
  /// ese mensaje, permite recuperar la clave de autenticación y falsificar
  /// cualquier backup. Por eso acá no hay un contador ni un nonce derivado del
  /// contenido, que son las dos formas habituales de arruinarlo cuando alguien
  /// intenta "hacerlo determinístico para poder deduplicar".
  @override
  Future<List<int>> encryptBytes(List<int> plaintext) async {
    final caja = await _aes.encrypt(plaintext, secretKey: _clave);
    // nonce ‖ ciphertext ‖ mac, en un solo bloque: `ArchivePort` sube una
    // ristra de bytes y no sabe —ni tiene por qué— que adentro hay estructura.
    return caja.concatenation();
  }

  @override
  Future<List<int>> decryptBytes(List<int> ciphertext) async {
    // Un bloque más corto que el sobre no puede ser nuestro. Sin este corte,
    // `fromConcatenation` tira un error de rango que no dice nada.
    if (ciphertext.length < _nonce + _mac) {
      throw const BackupIlegible('el bloque es más corto que su propio sobre');
    }

    final caja = SecretBox.fromConcatenation(
      ciphertext,
      nonceLength: _nonce,
      macLength: _mac,
    );

    try {
      return await _aes.decrypt(caja, secretKey: _clave);
    } on SecretBoxAuthenticationError {
      // No se distingue "clave equivocada" de "bytes alterados" y está bien:
      // desde acá son lo mismo, y las dos terminan igual —este backup no se
      // puede usar—. Lo que no puede pasar es devolver bytes y que el restore
      // siga adelante con ellos.
      throw const BackupIlegible(
        'no se pudo descifrar: o la clave no es la de este backup, o el '
        'contenido se alteró',
      );
    }
  }
}

/// El bloque no se puede descifrar: clave equivocada o contenido alterado.
///
/// Es un error de datos, no de programación, y por eso es `Exception` y no
/// `Error`: un backup corrupto en Drive es algo que puede pasar y que la app
/// tiene que poder contarle al colportor, no un bug que haya que arreglar.
class BackupIlegible implements Exception {
  const BackupIlegible(this.motivo);
  final String motivo;

  @override
  String toString() => 'BackupIlegible: $motivo';
}
