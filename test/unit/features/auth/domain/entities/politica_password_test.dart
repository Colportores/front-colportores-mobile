// Decisión de Cristian (02/10): la mayúscula es cualquier letra mayúscula (también con tilde y la
// Ñ) y el largo se cuenta por caracteres visibles. La misma política en registro y recuperación.
import 'package:colportores_mobile/features/auth/domain/entities/politica_password.dart';
import 'package:test/test.dart';

void main() {
  const requisitos = 'Usá al menos 8 caracteres, una mayúscula y un número.';

  group('mayúscula: cualquier letra mayúscula', () {
    test('las del alfabeto básico', () {
      expect(PoliticaPassword.tieneMayuscula('abcD'), isTrue);
    });

    test('con tilde, Ñ y diéresis cumplen', () {
      for (final c in ['Ñandú2026', 'Élan2026', 'úÓscar2026', 'pingÜino2026']) {
        expect(PoliticaPassword.tieneMayuscula(c), isTrue, reason: c);
        expect(PoliticaPassword.validar(c), isNull, reason: c);
      }
    });

    test('en minúscula, aunque lleve tilde o ñ, no cumple', () {
      for (final c in ['ñandú2026', 'élan20260', 'ünico1234']) {
        expect(PoliticaPassword.tieneMayuscula(c), isFalse, reason: c);
        expect(PoliticaPassword.validar(c), requisitos, reason: c);
      }
    });

    test('un dígito o un símbolo no es mayúscula', () {
      expect(PoliticaPassword.tieneMayuscula('12345678!@'), isFalse);
    });
  });

  group('largo por caracteres visibles', () {
    test('un emoji es 1, aunque ocupe varios códigos', () {
      expect(PoliticaPassword.largo('😀'), 1);
      expect(PoliticaPassword.largo('👨‍👩‍👧'), 1, reason: 'familia: varios códigos unidos');
      expect(PoliticaPassword.largo('🇺🇾'), 1, reason: 'bandera: dos códigos');
    });

    test('«é» escrita con una tilde combinada también es 1', () {
      expect(PoliticaPassword.largo('e\u0301'), 1);
    });

    test('con 7 caracteres visibles no cumple, aunque la cadena sea más larga', () {
      const siete = 'Ab1😀😀😀😀';
      expect(siete.length, greaterThan(8), reason: 'por unidades de código parecería largo');
      expect(PoliticaPassword.cumpleLargo(siete), isFalse);
      expect(PoliticaPassword.validar(siete), requisitos);
    });

    test('con 8 caracteres visibles cumple', () {
      expect(PoliticaPassword.cumpleLargo('Ab1😀😀😀😀😀'), isTrue);
      expect(PoliticaPassword.validar('Ab1😀😀😀😀😀'), isNull);
      expect(PoliticaPassword.validar('Ab1defgh'), isNull);
    });

    test('7 letras no, 8 sí (límite)', () {
      expect(PoliticaPassword.validar('Ab1defg'), requisitos);
      expect(PoliticaPassword.validar('Ab1defgh'), isNull);
    });
  });

  group('excedeLargoMaximo (tope de 72 bytes de Supabase Auth, #265)', () {
    test('72 caracteres ASCII entran; 73 no', () {
      expect(PoliticaPassword.excedeLargoMaximo('a' * 72), isFalse);
      expect(PoliticaPassword.excedeLargoMaximo('a' * 73), isTrue);
    });

    test('se cuenta en bytes UTF-8, no en caracteres: la ñ ocupa 2', () {
      expect(PoliticaPassword.excedeLargoMaximo('ñ' * 36), isFalse, reason: '72 bytes');
      expect(PoliticaPassword.excedeLargoMaximo('a${'ñ' * 36}'), isTrue, reason: '73 bytes');
      expect(PoliticaPassword.largo('ñ' * 37), 37, reason: 'pasa por bytes, no por largo');
      expect(PoliticaPassword.excedeLargoMaximo('ñ' * 37), isTrue);
    });

    test('un emoji ocupa 4 bytes', () {
      expect(PoliticaPassword.excedeLargoMaximo('😀' * 18), isFalse, reason: '72 bytes');
      expect(PoliticaPassword.excedeLargoMaximo('😀' * 19), isTrue, reason: '76 bytes');
    });

    test('la vacía y la de 8 no lo exceden', () {
      expect(PoliticaPassword.excedeLargoMaximo(''), isFalse);
      expect(PoliticaPassword.excedeLargoMaximo('Ab1defgh'), isFalse);
    });

    test('validar no mira el tope: la contraseña nueva de la vista 15 es #296', () {
      expect(PoliticaPassword.validar('Ab1${'x' * 100}'), isNull);
    });

    test('el texto del tope es el de la decisión del 02/10', () {
      expect(PoliticaPassword.demasiadoLarga, 'Es demasiado larga. Acortala.');
      expect(PoliticaPassword.largoMaximoBytes, 72);
    });
  });

  group('validar', () {
    test('sin número no cumple, aunque tenga mayúscula y largo', () {
      expect(PoliticaPassword.validar('Ñandúñandú'), requisitos);
    });

    test('vacía usa el texto que se le pase', () {
      expect(PoliticaPassword.validar(''), 'Ingresá tu contraseña');
      expect(PoliticaPassword.validar('', vacia: 'x'), 'x');
    });
  });
}
