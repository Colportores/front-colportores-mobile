// libsodium de verdad (la compilan los build hooks de `sodium` también para los tests). Argon2id con
// parámetros chicos para que sea rápido, salvo un caso con los de ADR-006.
import 'dart:typed_data';

import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:colportores_mobile/core/secure_storage/cripto_sodium.dart';
import 'package:colportores_mobile/core/secure_storage/envoltorio_dek.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:test/test.dart';

const _rapidos = ParametrosArgon2id(memoriaBytes: 64 * 1024, iteraciones: 1, paralelismo: 1);

Uint8List _sal(int valor) => Uint8List.fromList(List<int>.filled(EnvoltorioDek.bytesSal, valor));

ClaveDb _dek() => ClaveDb(Uint8List.fromList(List<int>.generate(32, (i) => i)));

void main() {
  late CriptoSodium cripto;

  setUp(() => cripto = CriptoSodium());

  group('CriptoSodium.derivar (Argon2id)', () {
    test('dada la misma contraseña, sal y parámetros, deriva la misma clave de 32 bytes', () async {
      final a = await cripto.derivar(password: 'secreto123', sal: _sal(1), parametros: _rapidos);
      final b = await cripto.derivar(password: 'secreto123', sal: _sal(1), parametros: _rapidos);

      expect(a.bytes, hasLength(32));
      expect(a.bytes, b.bytes);
    });

    test('dada otra contraseña u otra sal, deriva otra clave', () async {
      final base = await cripto.derivar(password: 'secreto123', sal: _sal(1), parametros: _rapidos);
      final otraPassword = await cripto.derivar(
        password: 'secreto124',
        sal: _sal(1),
        parametros: _rapidos,
      );
      final otraSal = await cripto.derivar(
        password: 'secreto123',
        sal: _sal(2),
        parametros: _rapidos,
      );

      expect(otraPassword.bytes, isNot(base.bytes));
      expect(otraSal.bytes, isNot(base.bytes));
    });

    test('con los parámetros de ADR-006 (64 MiB, t = 3) también deriva', () async {
      final clave = await cripto.derivar(
        password: 'secreto123',
        sal: _sal(1),
        parametros: ParametrosArgon2id.adr006,
      );

      expect(clave.bytes, hasLength(32));
    });

    test('la clave derivada se puede destruir (buffer mutable)', () async {
      final clave = await cripto.derivar(password: 'x', sal: _sal(1), parametros: _rapidos);

      expect(clave.destruir, returnsNormally);
    });

    test('dado p distinto de 1, lanza CriptoException: libsodium no lo puede reproducir', () async {
      await expectLater(
        cripto.derivar(
          password: 'secreto123',
          sal: _sal(1),
          parametros: const ParametrosArgon2id(
            memoriaBytes: 64 * 1024,
            iteraciones: 1,
            paralelismo: 2,
          ),
        ),
        throwsA(isA<CriptoException>()),
      );
    });

    test(
      'dados parámetros fuera de rango (una cabecera alterada), lanza CriptoException',
      () async {
        await expectLater(
          cripto.derivar(
            password: 'secreto123',
            sal: _sal(1),
            parametros: const ParametrosArgon2id(memoriaBytes: 1, iteraciones: 1, paralelismo: 1),
          ),
          throwsA(isA<CriptoException>()),
        );
      },
    );

    test('dada una sal de otro largo, lanza CriptoException', () async {
      await expectLater(
        cripto.derivar(password: 'secreto123', sal: Uint8List(3), parametros: _rapidos),
        throwsA(isA<CriptoException>()),
      );
    });
  });

  group('CriptoSodium.sellar / abrir (XChaCha20-Poly1305)', () {
    late ClaveEnvoltorio clave;
    final cabecera = Uint8List.fromList([1, 2, 3]);

    setUp(() async {
      clave = await cripto.derivar(password: 'secreto123', sal: _sal(1), parametros: _rapidos);
    });

    test('dada la misma clave y cabecera, abre la DEK que selló', () async {
      final sellado = await cripto.sellar(dek: _dek(), clave: clave, cabecera: cabecera);

      final dek = await cripto.abrir(
        nonce: sellado.nonce,
        cifrado: sellado.cifrado,
        clave: clave,
        cabecera: cabecera,
      );

      expect(dek.bytes, _dek().bytes);
      expect(dek.destruir, returnsNormally, reason: 'la DEK abierta es un buffer propio');
    });

    test('cada sellado usa un nonce nuevo', () async {
      final a = await cripto.sellar(dek: _dek(), clave: clave, cabecera: cabecera);
      final b = await cripto.sellar(dek: _dek(), clave: clave, cabecera: cabecera);

      expect(a.nonce, isNot(b.nonce));
      expect(a.cifrado, isNot(b.cifrado));
    });

    test('dada otra clave (otra contraseña), lanza EnvoltorioNoAbreException', () async {
      final sellado = await cripto.sellar(dek: _dek(), clave: clave, cabecera: cabecera);
      final otra = await cripto.derivar(password: 'otra', sal: _sal(1), parametros: _rapidos);

      await expectLater(
        cripto.abrir(
          nonce: sellado.nonce,
          cifrado: sellado.cifrado,
          clave: otra,
          cabecera: cabecera,
        ),
        throwsA(isA<EnvoltorioNoAbreException>()),
      );
    });

    test(
      'dada otra cabecera (parámetros o sal alterados), lanza EnvoltorioNoAbreException',
      () async {
        final sellado = await cripto.sellar(dek: _dek(), clave: clave, cabecera: cabecera);

        await expectLater(
          cripto.abrir(
            nonce: sellado.nonce,
            cifrado: sellado.cifrado,
            clave: clave,
            cabecera: Uint8List.fromList([1, 2, 4]),
          ),
          throwsA(isA<EnvoltorioNoAbreException>()),
        );
      },
    );

    test('dado un nonce de largo imposible, lanza EnvoltorioCorruptoException', () async {
      final sellado = await cripto.sellar(dek: _dek(), clave: clave, cabecera: cabecera);

      await expectLater(
        cripto.abrir(
          nonce: Uint8List(3),
          cifrado: sellado.cifrado,
          clave: clave,
          cabecera: cabecera,
        ),
        throwsA(isA<EnvoltorioCorruptoException>()),
      );
    });

    test('dado un envoltorio auténtico que no guarda 32 bytes, lanza '
        'EnvoltorioCorruptoException', () async {
      // Sellado a mano con la misma clave y cabecera: autentica, pero lo que guarda no es una DEK.
      final sodium = await SodiumSumoInit.init();
      final aead = sodium.crypto.aeadXChaCha20Poly1305IETF;
      final nonce = sodium.randombytes.buf(aead.nonceBytes);
      final clavePrivada = SecureKey.fromList(sodium, clave.bytes);
      final cifrado = aead.encrypt(
        message: Uint8List(16),
        nonce: nonce,
        key: clavePrivada,
        additionalData: cabecera,
      );
      clavePrivada.dispose();

      await expectLater(
        cripto.abrir(nonce: nonce, cifrado: cifrado, clave: clave, cabecera: cabecera),
        throwsA(isA<EnvoltorioCorruptoException>()),
      );
    });
  });
}
