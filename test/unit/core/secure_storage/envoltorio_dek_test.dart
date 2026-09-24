// Formato del envoltorio de la DEK (ADR-006): cabecera versionada + DEK cifrada. Dart puro.
import 'dart:convert';
import 'dart:typed_data';

import 'package:colportores_mobile/core/secure_storage/envoltorio_dek.dart';
import 'package:test/test.dart';

EnvoltorioDek _envoltorio({int version = 1}) => EnvoltorioDek(
  version: version,
  algoritmo: EnvoltorioDek.algoritmoActual,
  parametros: ParametrosArgon2id.adr006,
  sal: Uint8List.fromList(List<int>.filled(16, 1)),
  nonce: Uint8List.fromList(List<int>.filled(24, 2)),
  cifrado: Uint8List.fromList(List<int>.filled(48, 3)),
);

void main() {
  group('ParametrosArgon2id', () {
    test('los de ADR-006 son m = 64 MiB, t = 3, p = 1', () {
      expect(ParametrosArgon2id.adr006.memoriaBytes, 64 * 1024 * 1024);
      expect(ParametrosArgon2id.adr006.iteraciones, 3);
      expect(ParametrosArgon2id.adr006.paralelismo, 1);
    });
  });

  group('EnvoltorioDek', () {
    test('dado un envoltorio, cuando se codifica y se decodifica, queda igual', () {
      final original = _envoltorio();

      expect(EnvoltorioDek.decodificar(original.codificar()), original);
    });

    test('cuando se codifica, la cabecera lleva versión, algoritmo, m, t, p y sal', () {
      final json = jsonDecode(_envoltorio().codificar()) as Map<String, Object?>;

      expect(json['v'], 1);
      expect(json['alg'], 'argon2id13+xchacha20poly1305ietf');
      expect([json['m'], json['t'], json['p']], [64 * 1024 * 1024, 3, 1]);
      expect(base64Decode(json['sal']! as String), List<int>.filled(16, 1));
    });

    test('dado otra sal u otros parámetros, la cabecera autenticada cambia', () {
      final base = _envoltorio();
      final otraSal = EnvoltorioDek.cabeceraDe(
        version: 1,
        algoritmo: base.algoritmo,
        parametros: base.parametros,
        sal: Uint8List(16),
      );
      final otrosParametros = EnvoltorioDek.cabeceraDe(
        version: 1,
        algoritmo: base.algoritmo,
        parametros: const ParametrosArgon2id(memoriaBytes: 1024, iteraciones: 1, paralelismo: 1),
        sal: base.sal,
      );

      expect(otraSal, isNot(base.cabecera));
      expect(otrosParametros, isNot(base.cabecera));
    });

    test('cuando se imprime, no lleva ni la sal ni la DEK cifrada', () {
      final texto = _envoltorio().toString();

      expect(texto, 'EnvoltorioDek(v1, argon2id13+xchacha20poly1305ietf)');
    });

    group('dado un texto que no es un envoltorio que la app sepa abrir', () {
      Matcher corrupto(String motivo) => throwsA(
        isA<EnvoltorioCorruptoException>().having((e) => e.motivo, 'motivo', contains(motivo)),
      );

      Map<String, Object?> campos() =>
          jsonDecode(_envoltorio().codificar()) as Map<String, Object?>;

      test('cuando no es JSON, lanza EnvoltorioCorruptoException', () {
        expect(() => EnvoltorioDek.decodificar('no es json'), corrupto('JSON'));
      });

      test('cuando no es un objeto, lanza EnvoltorioCorruptoException', () {
        expect(() => EnvoltorioDek.decodificar('[1, 2]'), corrupto('objeto'));
      });

      test('cuando es de una versión posterior, lanza EnvoltorioPosteriorException: no está roto, '
          'hay que actualizar la app (#81)', () {
        expect(
          () => EnvoltorioDek.decodificar(_envoltorio(version: 2).codificar()),
          throwsA(isA<EnvoltorioPosteriorException>().having((e) => e.version, 'version', 2)),
        );
        expect(
          const EnvoltorioPosteriorException(2).toString(),
          'EnvoltorioPosteriorException(v2)',
        );
      });

      test('cuando m o t pasan los topes, lanza EnvoltorioCorruptoException: Argon2id no puede '
          'pedir toda la memoria ni congelar la recuperación (#81)', () {
        final mEnorme = campos()..['m'] = EnvoltorioDek.maxMemoriaBytes + 1;
        final tEnorme = campos()..['t'] = EnvoltorioDek.maxIteraciones + 1;
        final enElTope = campos()
          ..['m'] = EnvoltorioDek.maxMemoriaBytes
          ..['t'] = EnvoltorioDek.maxIteraciones;

        expect(() => EnvoltorioDek.decodificar(jsonEncode(mEnorme)), corrupto('"m"'));
        expect(() => EnvoltorioDek.decodificar(jsonEncode(tEnorme)), corrupto('"t"'));
        expect(EnvoltorioDek.decodificar(jsonEncode(enElTope)).parametros.iteraciones, 10);
        expect(EnvoltorioDek.maxMemoriaBytes, 256 * 1024 * 1024);
      });

      for (final campo in ['v', 'm', 't', 'p']) {
        test('cuando "$campo" falta o no es positivo, lanza EnvoltorioCorruptoException', () {
          final sinCampo = campos()..remove(campo);
          final negativo = campos()..[campo] = -1;

          expect(() => EnvoltorioDek.decodificar(jsonEncode(sinCampo)), corrupto(campo));
          expect(() => EnvoltorioDek.decodificar(jsonEncode(negativo)), corrupto(campo));
        });
      }

      test('cuando falta el algoritmo, lanza EnvoltorioCorruptoException', () {
        final sinAlgoritmo = campos()..['alg'] = '';

        expect(() => EnvoltorioDek.decodificar(jsonEncode(sinAlgoritmo)), corrupto('alg'));
      });

      for (final campo in ['sal', 'nonce', 'dek']) {
        test('cuando "$campo" falta o no es base64, lanza EnvoltorioCorruptoException', () {
          final sinCampo = campos()..remove(campo);
          final roto = campos()..[campo] = '¡no es base64!';

          expect(() => EnvoltorioDek.decodificar(jsonEncode(sinCampo)), corrupto(campo));
          expect(() => EnvoltorioDek.decodificar(jsonEncode(roto)), corrupto(campo));
        });
      }
    });
  });

  test('las excepciones del envoltorio no llevan contenido', () {
    expect(const EnvoltorioCorruptoException('no es JSON').toString(), contains('no es JSON'));
    expect(const EnvoltorioNoAbreException().toString(), 'EnvoltorioNoAbreException()');
  });
}
