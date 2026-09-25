import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Parámetros de costo de Argon2id con los que se derivó la clave de un envoltorio (ADR-006).
///
/// Viajan en la cabecera del envoltorio, así que se pueden subir más adelante sin romper los
/// envoltorios (ni los backups) viejos: cada uno se abre con los parámetros con los que se hizo.
final class ParametrosArgon2id extends Equatable {
  const ParametrosArgon2id({
    required this.memoriaBytes,
    required this.iteraciones,
    required this.paralelismo,
  });

  /// ADR-006: **m = 64 MiB, t = 3, p = 1**, la opción de memoria acotada de RFC 9106. Pendiente el
  /// spike en el Android más modesto: si pasa de ~2 s, se baja `t` y se mantiene la memoria.
  static const ParametrosArgon2id adr006 = ParametrosArgon2id(
    memoriaBytes: 64 * 1024 * 1024,
    iteraciones: 3,
    paralelismo: 1,
  );

  /// `m`, en bytes (libsodium la recibe en bytes).
  final int memoriaBytes;

  /// `t`, las pasadas sobre la memoria.
  final int iteraciones;

  /// `p`, los carriles. En libsodium vale siempre 1.
  final int paralelismo;

  @override
  List<Object?> get props => [memoriaBytes, iteraciones, paralelismo];
}

/// La DEK envuelta con Argon2id(contraseña): lo que se guarda en el archivo común, fuera del almacén
/// seguro, y lo que viaja con el backup (ADR-006).
///
/// Tiene una **cabecera versionada** —versión del formato, algoritmo, `m`, `t`, `p` y sal— y el
/// cifrado de la DEK con su nonce. La cabecera va autenticada junto con la DEK ([cabecera] es el
/// dato asociado del cifrado): si alguien la altera, el envoltorio no abre.
///
/// El formato en disco es JSON con los binarios en base64 ([codificar] / [decodificar]). Ningún
/// campo es secreto: la DEK va cifrada y la sal es pública.
final class EnvoltorioDek extends Equatable {
  const EnvoltorioDek({
    required this.version,
    required this.algoritmo,
    required this.parametros,
    required this.sal,
    required this.nonce,
    required this.cifrado,
  });

  /// Versión del formato que escribe esta app.
  static const int versionActual = 1;

  /// Argon2id v1.3 para derivar (libsodium `crypto_pwhash`) y XChaCha20-Poly1305 (IETF) para cifrar
  /// la DEK (libsodium `crypto_aead_xchacha20poly1305_ietf`). ADR-006 fija libsodium y Argon2id; el
  /// cifrado de la DEK no está escrito en el ADR y queda para confirmar en #26.
  static const String algoritmoActual = 'argon2id13+xchacha20poly1305ietf';

  /// `crypto_pwhash_SALTBYTES` de libsodium.
  static const int bytesSal = 16;

  /// Tope de `m` que la app acepta al leer un envoltorio: 4 veces el de ADR-006. Uno alterado o
  /// roto con un `m` enorme haría que Argon2id pidiera toda la memoria del teléfono.
  static const int maxMemoriaBytes = 256 * 1024 * 1024;

  /// Tope de `t` al leer un envoltorio, por lo mismo (un `t` enorme congelaría la recuperación).
  static const int maxIteraciones = 10;

  final int version;
  final String algoritmo;
  final ParametrosArgon2id parametros;
  final Uint8List sal;
  final Uint8List nonce;
  final Uint8List cifrado;

  /// Los bytes que se autentican junto con la DEK: la cabecera entera, en un orden fijo.
  Uint8List get cabecera =>
      cabeceraDe(version: version, algoritmo: algoritmo, parametros: parametros, sal: sal);

  /// La cabecera de un envoltorio que todavía no existe (hace falta para cifrar la DEK).
  static Uint8List cabeceraDe({
    required int version,
    required String algoritmo,
    required ParametrosArgon2id parametros,
    required Uint8List sal,
  }) => Uint8List.fromList(
    utf8.encode(
      jsonEncode([
        version,
        algoritmo,
        parametros.memoriaBytes,
        parametros.iteraciones,
        parametros.paralelismo,
        base64Encode(sal),
      ]),
    ),
  );

  /// El envoltorio como texto, para el archivo.
  String codificar() => jsonEncode({
    'v': version,
    'alg': algoritmo,
    'm': parametros.memoriaBytes,
    't': parametros.iteraciones,
    'p': parametros.paralelismo,
    'sal': base64Encode(sal),
    'nonce': base64Encode(nonce),
    'dek': base64Encode(cifrado),
  });

  /// Lee un envoltorio. Lanza [EnvoltorioPosteriorException] si lo escribió una versión más nueva
  /// de la app, y [EnvoltorioCorruptoException] si no es un envoltorio válido: formato roto, un
  /// campo que falta o parámetros de Argon2id fuera de los topes.
  static EnvoltorioDek decodificar(String texto) {
    final Object? json;
    try {
      json = jsonDecode(texto);
    } on FormatException {
      throw const EnvoltorioCorruptoException('no es JSON');
    }
    if (json is! Map<String, Object?>) {
      throw const EnvoltorioCorruptoException('no es un objeto');
    }

    final version = _entero(json, 'v');
    if (version > versionActual) throw EnvoltorioPosteriorException(version);
    return EnvoltorioDek(
      version: version,
      algoritmo: _texto(json, 'alg'),
      parametros: ParametrosArgon2id(
        memoriaBytes: _entero(json, 'm', maximo: maxMemoriaBytes),
        iteraciones: _entero(json, 't', maximo: maxIteraciones),
        paralelismo: _entero(json, 'p'),
      ),
      sal: _binario(json, 'sal'),
      nonce: _binario(json, 'nonce'),
      cifrado: _binario(json, 'dek'),
    );
  }

  static int _entero(Map<String, Object?> json, String campo, {int? maximo}) =>
      switch (json[campo]) {
        final int valor when valor > 0 && (maximo == null || valor <= maximo) => valor,
        final int _ when maximo != null => throw EnvoltorioCorruptoException(
          '"$campo" fuera de rango (tope $maximo)',
        ),
        _ => throw EnvoltorioCorruptoException('falta "$campo" o no es un entero positivo'),
      };

  static String _texto(Map<String, Object?> json, String campo) => switch (json[campo]) {
    final String valor when valor.isNotEmpty => valor,
    _ => throw EnvoltorioCorruptoException('falta "$campo"'),
  };

  static Uint8List _binario(Map<String, Object?> json, String campo) {
    final valor = json[campo];
    if (valor is! String) throw EnvoltorioCorruptoException('falta "$campo"');
    try {
      return base64Decode(valor);
    } on FormatException {
      throw EnvoltorioCorruptoException('"$campo" no es base64');
    }
  }

  @override
  List<Object?> get props => [version, algoritmo, parametros, sal, nonce, cifrado];

  /// Sin los binarios: la sal y el cifrado no son secretos, pero un log no los necesita.
  @override
  String toString() => 'EnvoltorioDek(v$version, $algoritmo)';
}

/// Lo que hay en el archivo del envoltorio no es un envoltorio que la app sepa abrir.
///
/// [toString] describe el motivo y nunca incluye el contenido.
final class EnvoltorioCorruptoException implements Exception {
  const EnvoltorioCorruptoException(this.motivo);

  final String motivo;

  @override
  String toString() => 'EnvoltorioCorruptoException($motivo)';
}

/// El envoltorio lo escribió una versión más nueva de la app: esta no sabe abrirlo, pero no está
/// roto. No se ofrece borrar nada: se pide actualizar la app.
final class EnvoltorioPosteriorException implements Exception {
  const EnvoltorioPosteriorException(this.version);

  final int version;

  @override
  String toString() => 'EnvoltorioPosteriorException(v$version)';
}

/// El envoltorio no abre con esa clave: la contraseña no es la que lo armó, o se alteró.
///
/// Nunca lleva la contraseña ni la clave.
final class EnvoltorioNoAbreException implements Exception {
  const EnvoltorioNoAbreException();

  @override
  String toString() => 'EnvoltorioNoAbreException()';
}
