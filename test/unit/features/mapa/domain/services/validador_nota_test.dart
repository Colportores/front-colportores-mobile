// Las reglas del texto de una nota de persona (HU-UBI-012). Dart puro.
import 'package:colportores_mobile/features/mapa/domain/services/validador_nota.dart';
import 'package:test/test.dart';

void main() {
  group('problema', () {
    test('dado un texto con contenido, cuando se valida, sirve', () {
      expect(ValidadorNota.problema('Le interesa Caminos de la Vida'), isNull);
    });

    test(
      'dado un texto vacío, nulo o solo de espacios y saltos de línea, cuando se valida, es vacío',
      () {
        for (final texto in [null, '', '   ', '\n\n', ' \t\n ']) {
          expect(ValidadorNota.problema(texto), ProblemaNota.vacia, reason: 'texto: "$texto"');
        }
      },
    );

    test('dado un texto solo de caracteres invisibles, cuando se valida, es vacío', () {
      // U+200B (espacio de ancho cero) y U+FEFF no son espacios para `trim`, pero no dicen nada.
      expect(ValidadorNota.problema('​​'), ProblemaNota.vacia);
      expect(ValidadorNota.problema('﻿ ​'), ProblemaNota.vacia);
    });

    test('dado un emoji solo, cuando se valida, sirve', () {
      expect(ValidadorNota.problema('👍'), isNull);
    });

    test('dado el aviso del problema, cuando se lo pide, dice qué hacer', () {
      expect(ValidadorNota.mensaje(ProblemaNota.vacia), 'Escribí la nota para poder guardarla.');
    });
  });

  group('limpiar', () {
    test('dado un texto con espacios y saltos en los bordes, cuando se limpia, los pierde', () {
      expect(ValidadorNota.limpiar('  \n hola \n '), 'hola');
    });

    test('dado un texto con renglones por dentro, cuando se limpia, los conserva', () {
      expect(ValidadorNota.limpiar('uno\n\ndos  tres'), 'uno\n\ndos  tres');
    });

    test('dado nulo, cuando se limpia, queda vacío', () {
      expect(ValidadorNota.limpiar(null), '');
    });
  });

  group('límite blando de 5000 caracteres', () {
    test('dado exactamente 5000 caracteres, cuando se mide, no supera el límite', () {
      expect(ValidadorNota.superaElLimite('a' * 5000), isFalse);
      expect(ValidadorNota.largo('a' * 5000), 5000);
    });

    test('dado 5001 caracteres, cuando se mide, supera el límite', () {
      expect(ValidadorNota.superaElLimite('a' * 5001), isTrue);
    });

    test('dado un emoji (dos unidades UTF-16), cuando se cuenta, vale un carácter', () {
      expect(ValidadorNota.largo('👍' * 5000), 5000);
      expect(ValidadorNota.superaElLimite('👍' * 5000), isFalse);
      expect(ValidadorNota.superaElLimite('👍' * 5001), isTrue);
    });

    test('dado un texto con espacios en los bordes, cuando se cuenta, no los cuenta', () {
      expect(ValidadorNota.largo('   ${'a' * 5000}   '), 5000);
    });
  });
}
