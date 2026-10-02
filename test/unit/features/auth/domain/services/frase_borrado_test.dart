// HU-AUTH-010, vista 19: la frase que se escribe para confirmar el borrado.
import 'package:colportores_mobile/features/auth/domain/services/frase_borrado.dart';
import 'package:test/test.dart';

void main() {
  group('FraseBorrado.para', () {
    test('nombre y apellido en mayúsculas con guiones', () {
      expect(FraseBorrado.para('Lucía Silva'), 'BORRAR-DATOS-LUCIA-SILVA');
    });

    test('sin tildes y con ñ → N', () {
      expect(FraseBorrado.para('Íñigo Muñoz Ávila'), 'BORRAR-DATOS-INIGO-MUNOZ-AVILA');
    });

    test('espacios de más y de los bordes no hacen guiones de más', () {
      expect(FraseBorrado.para('  Ana   María  Pérez '), 'BORRAR-DATOS-ANA-MARIA-PEREZ');
    });

    test('un nombre con guion o apóstrofe queda armable', () {
      expect(FraseBorrado.para("Jean-Luc O'Brien"), 'BORRAR-DATOS-JEAN-LUC-OBRIEN');
    });

    test('sin nombre (o sin letras) no hay frase', () {
      expect(FraseBorrado.para(null), isNull);
      expect(FraseBorrado.para(''), isNull);
      expect(FraseBorrado.para(' - . '), isNull);
    });
  });

  group('FraseBorrado.coincide', () {
    const esperada = 'BORRAR-DATOS-LUCIA-SILVA';

    test('no distingue mayúsculas', () {
      expect(FraseBorrado.coincide('borrar-datos-lucia-silva', esperada), isTrue);
      expect(FraseBorrado.coincide('Borrar-Datos-Lucia-Silva', esperada), isTrue);
    });

    test('ignora los espacios de los bordes, no los del medio', () {
      expect(FraseBorrado.coincide(' BORRAR-DATOS-LUCIA-SILVA ', esperada), isTrue);
      expect(FraseBorrado.coincide('BORRAR DATOS LUCIA SILVA', esperada), isFalse);
    });

    test('una frase distinta o incompleta no coincide', () {
      expect(FraseBorrado.coincide('BORRAR-DATOS-LUCIA', esperada), isFalse);
      expect(FraseBorrado.coincide('', esperada), isFalse);
    });
  });
}
