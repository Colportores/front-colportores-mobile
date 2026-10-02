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
