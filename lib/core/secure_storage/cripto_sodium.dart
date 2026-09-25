import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'clave_db.dart';
import 'envoltorio_dek.dart';

/// [ProveedorClaveDb] y [SelladorDek] sobre libsodium (ADR-006, S11), vía `package:sodium`.
///
/// Es el **único** archivo del proyecto que conoce libsodium. Argon2id es `crypto_pwhash` con el
/// algoritmo Argon2id v1.3 y corre **fuera del isolate de la UI** (`runIsolated`, R13): con los
/// parámetros de ADR-006 tarda de 1 a 2 s. El cifrado de la DEK es
/// `crypto_aead_xchacha20poly1305_ietf`, con la cabecera del envoltorio como dato asociado.
///
/// libsodium se carga la primera vez que se usa, no al construir: los builds hooks de `sodium` la
/// compilan para cada plataforma y la empaquetan con la app. La API de `crypto_pwhash` es de la
/// variante "sumo", que en nativo es la misma biblioteca.
///
/// Nunca loguea ni pone en una excepción la contraseña, la clave ni la DEK. Las fallas de la
/// librería salen como [CriptoException]; una DEK que no abre, como [EnvoltorioNoAbreException].
final class CriptoSodium implements ProveedorClaveDb, SelladorDek {
  CriptoSodium({FutureOr<SodiumSumo> Function()? inicializar})
    : _inicializar = inicializar ?? SodiumSumoInit.init;

  final FutureOr<SodiumSumo> Function() _inicializar;
  SodiumSumo? _sodium;

  Future<SodiumSumo> _libsodium() async => _sodium ??= await _inicializar();

  @override
  Future<ClaveEnvoltorio> derivar({
    required String password,
    required Uint8List sal,
    required ParametrosArgon2id parametros,
  }) async {
    if (parametros.paralelismo != 1) {
      // En libsodium p vale siempre 1: otro valor no se puede reproducir y el envoltorio no abriría.
      throw const CriptoException('derivar', 'libsodium solo deriva con p = 1');
    }
    final sodium = await _libsodium();
    final passwordBytes = Int8List.fromList(utf8.encode(password));
    try {
      final bytes = await sodium.runIsolated((_, _) {
        final clave = sodium.crypto.pwhash(
          outLen: ClaveDb.bytesEsperados,
          password: passwordBytes,
          salt: sal,
          opsLimit: parametros.iteraciones,
          memLimit: parametros.memoriaBytes,
          alg: CryptoPwhashAlgorithm.argon2id13,
        );
        try {
          return clave.extractBytes();
        } finally {
          clave.dispose();
          // La copia de la contraseña que viajó a este isolate.
          passwordBytes.fillRange(0, passwordBytes.length, 0);
        }
      });
      return ClaveEnvoltorio(bytes);
    } on SodiumException {
      throw const CriptoException('derivar', 'libsodium no pudo derivar');
    } on ArgumentError {
      // Parámetros fuera de los rangos de libsodium (un envoltorio alterado, por ejemplo). Sin el
      // mensaje: podría nombrar el largo de la contraseña.
      throw const CriptoException('derivar', 'parámetros fuera de rango');
    } finally {
      passwordBytes.fillRange(0, passwordBytes.length, 0);
    }
  }

  @override
  Future<({Uint8List nonce, Uint8List cifrado})> sellar({
    required ClaveDb dek,
    required ClaveEnvoltorio clave,
    required Uint8List cabecera,
  }) async {
    final sodium = await _libsodium();
    final aead = sodium.crypto.aeadXChaCha20Poly1305IETF;
    final clavePrivada = SecureKey.fromList(sodium, clave.bytes);
    try {
      final nonce = sodium.randombytes.buf(aead.nonceBytes);
      final cifrado = aead.encrypt(
        message: dek.bytes,
        nonce: nonce,
        key: clavePrivada,
        additionalData: cabecera,
      );
      return (nonce: nonce, cifrado: cifrado);
    } on SodiumException {
      throw const CriptoException('sellar', 'libsodium no pudo cifrar la DEK');
    } finally {
      clavePrivada.dispose();
    }
  }

  @override
  Future<ClaveDb> abrir({
    required Uint8List nonce,
    required Uint8List cifrado,
    required ClaveEnvoltorio clave,
    required Uint8List cabecera,
  }) async {
    final sodium = await _libsodium();
    final aead = sodium.crypto.aeadXChaCha20Poly1305IETF;
    final clavePrivada = SecureKey.fromList(sodium, clave.bytes);
    try {
      final dek = aead.decrypt(
        cipherText: cifrado,
        nonce: nonce,
        key: clavePrivada,
        additionalData: cabecera,
      );
      // Copia propia y mutable (ClaveDb la tiene que poder destruir), y el original en ceros.
      final copia = Uint8List.fromList(dek);
      _pisar(dek);
      if (copia.length != ClaveDb.bytesEsperados) {
        _pisar(copia);
        throw const EnvoltorioCorruptoException('la DEK descifrada no tiene 32 bytes');
      }
      return ClaveDb(copia);
    } on SodiumException {
      // El tag no verifica: otra contraseña, u otra cabecera.
      throw const EnvoltorioNoAbreException();
    } on ArgumentError {
      // Nonce o cifrado de un largo imposible: el archivo no es un envoltorio válido.
      throw const EnvoltorioCorruptoException('nonce o cifrado de largo inválido');
    } finally {
      clavePrivada.dispose();
    }
  }

  /// Best-effort, como `ClaveDb.destruir`: si la librería devolvió una vista inmutable, queda para
  /// el recolector.
  static void _pisar(Uint8List bytes) {
    try {
      bytes.fillRange(0, bytes.length, 0);
    } on UnsupportedError {
      // Vista inmutable: no hay forma de pisarla.
    }
  }
}
