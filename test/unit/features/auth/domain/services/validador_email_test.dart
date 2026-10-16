// Test de dominio: Dart puro. No importa Flutter, Drift ni Supabase (CLAUDE.md §Tests).
import 'package:colportores_mobile/features/auth/domain/services/validador_email.dart';
import 'package:test/test.dart';

import '../../../../../helpers/casos_email.dart';

void main() {
  group('ValidadorEmail (#353)', () {
    group('dado un email válido', () {
      for (final email in [
        'lucia@correo.com',
        'LUCIA@CORREO.COM',
        'ana@sub.dominio.com',
        'ana@mi-correo.com',
        'ana@correo.co',
        '1.234.567@correo.com',
        ...emailsValidosRaros,
      ]) {
        test('«$email» pasa', () {
          expect(ValidadorEmail.problema(email), isNull);
          expect(ValidadorEmail.mensaje(email, siIncompleto: 'x'), isNull);
        });
      }
    });

    group('dado un email con un carácter que el servidor no acepta', () {
      for (final email in [
        ...emailsConCaracterNoPermitido,
        'lucia@correo.com ',
        ' lucia@correo.com',
        'lucia\t@correo.com',
        'lucia@correo.com\n',
        'lucia@correo.com;',
        'lu(cia)@correo.com',
        'lu<cia>@correo.com',
        r'lu\cia@correo.com',
      ]) {
        test('«${email.replaceAll('\n', r'\n').replaceAll('\t', r'\t')}» es carácter no '
            'permitido', () {
          expect(ValidadorEmail.problema(email), ProblemaEmail.caracterNoPermitido);
          expect(
            ValidadorEmail.mensaje(email, siIncompleto: 'x'),
            'Revisá el email: no puede llevar tildes, ñ, espacios ni comas.',
          );
        });
      }

      test('el aviso es el literal de la decisión, el mismo para todas las pantallas', () {
        expect(ValidadorEmail.avisoCaracterNoPermitido, avisoCaracterNoPermitido);
      });

      test('cuando además falta la @, el carácter de más es lo primero que se avisa', () {
        expect(ValidadorEmail.problema('lucia correo.com'), ProblemaEmail.caracterNoPermitido);
      });
    });

    group('dado un email incompleto o mal armado', () {
      for (final email in [
        ...emailsIncompletos,
        'lucia@correo.com..',
        'lucia@correo.',
        '1.234.567-8',
        '12345678',
        'a@b@correo.com',
        // Un carácter de los que van antes de la @, pero en el dominio: está mal armado.
        'ana@correo_x.com',
        'ana@correo!x.com',
      ]) {
        test('«$email» queda con el texto de cada pantalla', () {
          expect(ValidadorEmail.problema(email), ProblemaEmail.incompleto);
          expect(
            ValidadorEmail.mensaje(email, siIncompleto: 'El texto de la pantalla'),
            'El texto de la pantalla',
          );
        });
      }
    });

    group('dado el largo', () {
      const dominio = '@correo.com';

      test('cuando mide justo 254 caracteres, pasa', () {
        final email = '${'a' * (ValidadorEmail.largoMaximo - dominio.length)}$dominio';

        expect(email.length, 254);
        expect(ValidadorEmail.problema(email), isNull);
      });

      test('cuando mide 255, es un email incompleto (no es un email)', () {
        final email = '${'a' * (ValidadorEmail.largoMaximo + 1 - dominio.length)}$dominio';

        expect(email.length, 255);
        expect(ValidadorEmail.problema(email), ProblemaEmail.incompleto);
      });

      test('cuando una etiqueta del dominio mide 63, pasa; con 64, no', () {
        expect(ValidadorEmail.problema('ana@${'a' * 63}.com'), isNull);
        expect(ValidadorEmail.problema('ana@${'a' * 64}.com'), ProblemaEmail.incompleto);
      });
    });

    group('dado el campo vacío', () {
      test('no es un email (pedirlo es de cada pantalla)', () {
        expect(ValidadorEmail.problema(''), ProblemaEmail.incompleto);
      });
    });

    test('el aviso de la dirección que el servidor rechaza es el literal de la decisión', () {
      expect(ValidadorEmail.avisoDireccionRechazada, avisoDireccionRechazada);
    });
  });

  group('ValidadorEmail.normalizar (#353, decisión del 16/10 sobre el PR #354)', () {
    test('recorta los espacios y pasa a minúsculas', () {
      expect(ValidadorEmail.normalizar('  Ana@Example.COM '), 'ana@example.com');
      expect(ValidadorEmail.normalizar('\tLUCIA@correo.com\n'), emailLimpio);
    });

    test('un email limpio queda igual, con todos los caracteres que acepta el servidor', () {
      for (final email in [emailLimpio, ...emailsValidosRaros]) {
        expect(ValidadorEmail.normalizar(email), email.toLowerCase());
      }
    });

    for (final c in invisiblesDeFormato) {
      group('dado el carácter invisible ${codigoUnicode(c)}', () {
        test('cuando está en el medio, lo borra', () {
          for (final email in emailsConInvisibleEnElMedio(c)) {
            expect(ValidadorEmail.normalizar(email), emailLimpio, reason: email.runes.toString());
          }
        });

        test('cuando está al borde (con o sin espacios alrededor), lo borra', () {
          for (final email in emailsConInvisibleAlBorde(c)) {
            expect(ValidadorEmail.normalizar(email), emailLimpio, reason: email.runes.toString());
          }
        });

        test('el email que queda pasa el validador (no se avisa de lo que la persona no ve)', () {
          for (final email in [
            ...emailsConInvisibleEnElMedio(c),
            ...emailsConInvisibleAlBorde(c),
          ]) {
            expect(ValidadorEmail.problema(ValidadorEmail.normalizar(email)), isNull);
          }
        });
      });
    }

    test('un email que solo tiene invisibles y espacios queda vacío', () {
      final todos = String.fromCharCodes(invisiblesDeFormato);

      expect(ValidadorEmail.normalizar(todos), isEmpty);
      expect(ValidadorEmail.normalizar(' $todos '), isEmpty);
    });

    test('no borra lo que sí se ve: la tilde, la ñ, el espacio del medio y la coma siguen', () {
      for (final email in ['lucía@correo.com', 'muñoz@correo.com', 'lu cia@correo.com']) {
        expect(ValidadorEmail.normalizar(email), email);
      }
      expect(ValidadorEmail.normalizar('lucia,@correo.com'), 'lucia,@correo.com');
      expect(
        ValidadorEmail.problema(ValidadorEmail.normalizar('lu\u200Bcía@correo.com')),
        ProblemaEmail.caracterNoPermitido,
      );
    });
  });
}
