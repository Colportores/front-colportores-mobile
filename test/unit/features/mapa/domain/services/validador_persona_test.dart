// Reglas de los campos del alta de una persona (HU-UBI-008, vista 32A·03 y 32A·04).
import 'package:colportores_mobile/features/mapa/domain/services/validador_persona.dart';
import 'package:test/test.dart';

void main() {
  group('nombre', () {
    test('dado un nombre vacío o en blanco, cuando se valida, es vacío', () {
      expect(ValidadorPersona.problemaNombre(null), ProblemaNombre.vacio);
      expect(ValidadorPersona.problemaNombre(''), ProblemaNombre.vacio);
      expect(ValidadorPersona.problemaNombre('   \t '), ProblemaNombre.vacio);
    });

    test('dado un nombre de un solo carácter, cuando se valida, es corto', () {
      expect(ValidadorPersona.problemaNombre('A'), ProblemaNombre.corto);
      expect(ValidadorPersona.problemaNombre('  A  '), ProblemaNombre.corto);
    });

    test('dado un nombre de dos caracteres o más, cuando se valida, sirve', () {
      expect(ValidadorPersona.problemaNombre('Jo'), isNull);
      expect(ValidadorPersona.problemaNombre('  María José '), isNull);
    });

    test('dado un emoji (dos unidades UTF-16), cuando se cuenta, vale un carácter', () {
      expect(ValidadorPersona.problemaNombre('😀'), ProblemaNombre.corto);
      expect(ValidadorPersona.problemaNombre('😀😀'), isNull);
    });

    test('dado cada problema, cuando se pide su texto, el vacío dice lo del canvas', () {
      expect(ValidadorPersona.mensajeNombre(ProblemaNombre.vacio), 'Escribí al menos el nombre.');
      expect(ValidadorPersona.mensajeNombre(ProblemaNombre.corto), contains('2 letras'));
    });
  });

  group('teléfono', () {
    test('dado un teléfono vacío o solo separadores, cuando se valida, sirve (es opcional)', () {
      expect(ValidadorPersona.problemaTelefono(null), isNull);
      expect(ValidadorPersona.problemaTelefono(''), isNull);
      expect(ValidadorPersona.problemaTelefono('  '), isNull);
    });

    test('dado un celular uruguayo completo, con o sin espacios, cuando se valida, sirve', () {
      expect(ValidadorPersona.problemaTelefono('099123456'), isNull);
      expect(ValidadorPersona.problemaTelefono('099 123 456'), isNull);
      expect(ValidadorPersona.problemaTelefono('(099) 123-456'), isNull);
    });

    test('dado el canvas 32A·04 «099 12», cuando se valida, es incompleto', () {
      expect(ValidadorPersona.problemaTelefono('099 12'), ProblemaTelefono.incompleto);
      expect(
        ValidadorPersona.mensajeTelefono(ProblemaTelefono.incompleto),
        'Revisá el teléfono: le faltan números.',
      );
    });

    test('dado un celular con un dígito de más, cuando se valida, sobran', () {
      expect(ValidadorPersona.problemaTelefono('0991234567'), ProblemaTelefono.sobran);
    });

    test('dado un número con +598, cuando se valida, pide 8 dígitos después del prefijo', () {
      expect(ValidadorPersona.problemaTelefono('+598 99 123 456'), isNull);
      expect(ValidadorPersona.problemaTelefono('+59899123456'), isNull);
      expect(ValidadorPersona.problemaTelefono('+598 99 123'), ProblemaTelefono.incompleto);
      expect(ValidadorPersona.problemaTelefono('+598991234567'), ProblemaTelefono.sobran);
    });

    test('dado un número del exterior, un fijo o cualquier otro que no empieza con 09 ni +598, '
        'cuando se valida, no se bloquea', () {
      expect(ValidadorPersona.problemaTelefono('+54 9 11 5555 1234'), isNull);
      expect(ValidadorPersona.problemaTelefono('2 900 1234'), isNull);
      expect(ValidadorPersona.problemaTelefono('42 22 33 44'), isNull);
    });

    test('dado letras u otros símbolos, cuando se valida, hay caracteres no válidos', () {
      expect(ValidadorPersona.problemaTelefono('abc123'), ProblemaTelefono.caracteres);
      expect(ValidadorPersona.problemaTelefono('099 12x 456'), ProblemaTelefono.caracteres);
      expect(ValidadorPersona.problemaTelefono('099+123456'), ProblemaTelefono.caracteres);
    });
  });

  group('textos guardados', () {
    test('dado texto con espacios de más, cuando se limpia, queda con uno solo entre palabras', () {
      expect(ValidadorPersona.limpiar('  Ana   María \n'), 'Ana María');
    });

    test('dado un teléfono con espacios de más, cuando se limpia, conserva el formato escrito', () {
      expect(ValidadorPersona.telefonoLimpio(' 099  123 456 '), '099 123 456');
    });

    test('dado un teléfono vacío, cuando se limpia, queda nulo', () {
      expect(ValidadorPersona.telefonoLimpio('   '), isNull);
      expect(ValidadorPersona.telefonoLimpio(null), isNull);
    });
  });
}
