// La mitad de ADR-003 que no es de plataforma: comprimir, hashear y sacar el
// trabajo pesado del hilo de la UI.
//
// El adaptador nativo que falta —`cryptography_flutter` sobre el crypto del
// OS— solo tiene que implementar dos métodos: cifrar y descifrar un bloque de
// bytes. Todo lo demás ya está acá y corre en la VM, así que se testea sin
// dispositivo.

import 'dart:convert';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../core/ports.dart';

/// Un [CryptoPort] que comprime antes de cifrar y hashea con SHA-256.
///
/// **El orden importa y no es negociable**: primero comprimir, después cifrar.
/// Al revés no sirve de nada — un ciphertext bien construido es indistinguible
/// de ruido, y el ruido no comprime. Un backup de la DB de un colportor son
/// mayormente strings repetidos: comprimir antes es la diferencia entre subir
/// megabytes o cientos de kilobytes por su plan de datos.
///
/// Lo único que pone la plataforma es [encryptBytes] / [decryptBytes]:
///
/// ```dart
/// class NativeCrypto extends CompressingCrypto {
///   NativeCrypto(this._clave);
///   final SecretKey _clave;
///
///   @override
///   Future<List<int>> encryptBytes(List<int> plaintext) async { /* AES-GCM */ }
///   @override
///   Future<List<int>> decryptBytes(List<int> ciphertext) async { /* … */ }
/// }
/// ```
abstract class CompressingCrypto implements CryptoPort {
  const CompressingCrypto({this.isolateThreshold = 64 * 1024});

  /// A partir de cuántos bytes conviene mandar el trabajo a un isolate.
  ///
  /// Debajo de este tamaño, arrancar el isolate cuesta más que comprimir. El
  /// backup incremental de un rato de trabajo suele quedar por debajo; el
  /// completo, muy por encima.
  final int isolateThreshold;

  /// Cifrado del bloque, con la clave del usuario. Lo pone la plataforma.
  Future<List<int>> encryptBytes(List<int> plaintext);

  /// Descifrado del bloque.
  Future<List<int>> decryptBytes(List<int> ciphertext);

  @override
  Future<List<int>> encrypt(List<int> plaintext) async =>
      encryptBytes(await compress(plaintext));

  @override
  Future<List<int>> decrypt(List<int> ciphertext) async =>
      decompress(await decryptBytes(ciphertext));

  /// Hash del payload cifrado, para `verifyChain()` (HU-SYNC-009).
  ///
  /// Es sobre el ciphertext a propósito: el motor puede verificar la integridad
  /// de la cadena sin descifrar nada, y por lo tanto sin la clave del usuario.
  @override
  String digest(List<int> bytes) => sha256.convert(bytes).toString();

  /// La firma se calcula con [sign] (lo pone la plataforma, que tiene la llave)
  /// y se compara acá, en tiempo constante: no se corta en la primera diferencia
  /// (quien mira la carpeta de Drive no puede ir probando byte a byte).
  @override
  Future<bool> verifySignature(String mensaje, String? firma) async {
    if (firma == null) return false;
    final esperada = utf8.encode(await sign(mensaje));
    final recibida = utf8.encode(firma);
    // El largo de una firma válida no es secreto: sale del algoritmo.
    if (esperada.length != recibida.length) return false;
    var diferencia = 0;
    for (var i = 0; i < esperada.length; i++) {
      diferencia |= esperada[i] ^ recibida[i];
    }
    return diferencia == 0;
  }

  /// gzip, en un isolate si el payload lo justifica.
  ///
  /// `Isolate.run` es lo que mantiene la UI a 60 fps mientras se arma el backup
  /// del cierre de jornada (Apéndice A).
  Future<List<int>> compress(List<int> datos) => _quizasEnIsolate(datos, _gzip);

  Future<List<int>> decompress(List<int> datos) =>
      _quizasEnIsolate(datos, _gunzip);

  Future<List<int>> _quizasEnIsolate(
    List<int> datos,
    List<int> Function(List<int>) trabajo,
  ) async {
    if (datos.length < isolateThreshold) return trabajo(datos);
    return Isolate.run(() => trabajo(datos));
  }
}

// Funciones de nivel superior: lo que corre en un isolate no puede capturar
// `this`.

List<int> _gzip(List<int> datos) => GZipEncoder().encode(datos);

List<int> _gunzip(List<int> datos) => GZipDecoder().decodeBytes(datos);
