// Test del tipo de la clave de la DB: Dart puro.
import 'dart:typed_data';

import 'package:colportores_mobile/core/secure_storage/clave_db.dart';
import 'package:test/test.dart';

Uint8List _bytes(int largo) => Uint8List.fromList(List<int>.filled(largo, 7));

void main() {
  group('ClaveDb', () {
    group('dado que la clave tiene el largo de AES-256', () {
      test('cuando se construye, conserva los 32 bytes tal cual', () {
        final clave = ClaveDb(_bytes(ClaveDb.bytesEsperados));

        expect(clave.bytes, hasLength(32));
        expect(
          clave.bytes.every((b) => b == 7),
          isTrue,
          reason: 'la prueba de escritura no altera',
        );
        expect(clave.destruida, isFalse);
      });
    });

    group('dado que la clave tiene otro largo', () {
      test('cuando se construye con menos bytes, lanza ArgumentError', () {
        expect(() => ClaveDb(_bytes(16)), throwsA(isA<ArgumentError>()));
      });

      test('cuando se construye con más bytes, lanza ArgumentError', () {
        expect(() => ClaveDb(_bytes(64)), throwsA(isA<ArgumentError>()));
      });
    });

    group('dado que el buffer es una vista inmutable', () {
      // Compila igual que un Uint8List común, pero destruir() no podría sobrescribirlo y la
      // clave quedaría viva detrás de un `destruida` en false.
      late Uint8List inmutable;

      setUp(() => inmutable = _bytes(ClaveDb.bytesEsperados).asUnmodifiableView());

      test('cuando se construye, lanza ArgumentError sin llegar a usarse', () {
        expect(() => ClaveDb(inmutable), throwsA(isA<ArgumentError>()));
      });

      test('cuando se rechaza, el mensaje del error no incluye los bytes', () {
        expect(
          () => ClaveDb(inmutable),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.toString(),
              'toString',
              allOf(isNot(contains('7')), isNot(contains('['))),
            ),
          ),
        );
      });
    });

    group('dado que se cierra la sesión', () {
      test('cuando se destruye, los bytes quedan en cero y el acceso falla', () {
        final crudos = _bytes(ClaveDb.bytesEsperados);
        final clave = ClaveDb(crudos);

        clave.destruir();

        expect(crudos.every((b) => b == 0), isTrue, reason: 'el buffer se sobrescribe');
        expect(clave.destruida, isTrue);
        expect(() => clave.bytes, throwsA(isA<StateError>()));
      });

      test('cuando se destruye dos veces, no lanza', () {
        final clave = ClaveDb(_bytes(ClaveDb.bytesEsperados))..destruir();

        expect(clave.destruir, returnsNormally);
      });
    });

    test('cuando se imprime, no expone los bytes', () {
      final clave = ClaveDb(_bytes(ClaveDb.bytesEsperados));

      expect(clave.toString(), 'ClaveDb(oculta)');
      expect(clave.toString(), isNot(contains('7')));
    });
  });
}
