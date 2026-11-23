// HU-UBI-010, caso borde «Cambio total de nombre» (canvas 32C·03): el aviso «¿Es otra persona?» sale
// cuando cambian el nombre y el apellido a la vez (decisión de Cristian del 27/10). Se compara sin
// mayúsculas, sin tildes y sin espacios de más; un apellido vacío que se completa no cuenta.
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_otra_persona.dart';
import 'package:test/test.dart';

import '../../../../../helpers/persona_falsos.dart';

void main() {
  const criterio = CriterioOtraPersonaPorNombreYApellido();

  Persona persona({String nombre = 'María', String apellido = 'Fernández'}) => Persona(
    id: 'per-1',
    nombre: nombre,
    apellido: apellido,
    telefono: '099 123 456',
    auditoria: auditoriaPersonas(),
  );

  bool parece(Persona antes, String nombre, String apellido, [String telefono = '099 123 456']) =>
      criterio.pareceOtraPersona(antes, (nombre: nombre, apellido: apellido, telefono: telefono));

  group('cuando cambian el nombre y el apellido a la vez', () {
    test('dado el cambio total del canvas (Roberto Suárez, otro teléfono), sale el aviso', () {
      expect(parece(persona(), 'Roberto', 'Suárez', '091 222 333'), isTrue);
    });

    test('dado el mismo cambio con el teléfono igual, sale igual: el teléfono no entra', () {
      expect(parece(persona(), 'Roberto', 'Suárez'), isTrue);
    });

    test('dado un cambio con otras mayúsculas y espacios de más en el nombre nuevo, sale', () {
      expect(parece(persona(), '  roberto ', ' SUÁREZ  '), isTrue);
    });
  });

  group('cuando no cambian los dos', () {
    test('dado «Fernandez» → «Fernández» (solo una tilde), no sale el aviso', () {
      expect(parece(persona(apellido: 'Fernandez'), 'María', 'Fernández'), isFalse);
    });

    test('dado que se corrigen las tildes de los dos campos, no sale el aviso', () {
      expect(
        parece(persona(nombre: 'Maria', apellido: 'Fernandez'), 'María', 'Fernández'),
        isFalse,
      );
    });

    test('dado que cambia solo el apellido, no sale el aviso', () {
      expect(parece(persona(), 'María', 'Suárez'), isFalse);
    });

    test('dado que cambia solo el nombre, no sale el aviso', () {
      expect(parece(persona(), 'Roberto', 'Fernández'), isFalse);
    });

    test('dado que cambia solo el teléfono, no sale el aviso', () {
      expect(parece(persona(), 'María', 'Fernández', '091 222 333'), isFalse);
    });

    test('dado un cambio solo de mayúsculas y espacios de más, no sale el aviso', () {
      expect(parece(persona(), '  MARÍA ', 'fernández  '), isFalse);
      expect(parece(persona(apellido: 'Fernández Pérez'), 'María', 'Fernández  Pérez'), isFalse);
    });

    test('dado que no cambia nada, no sale el aviso', () {
      expect(parece(persona(), 'María', 'Fernández'), isFalse);
    });
  });

  group('cuando el apellido estaba vacío', () {
    test('dado apellido vacío → completo con el mismo nombre, no sale el aviso', () {
      expect(parece(persona(apellido: ''), 'María', 'Fernández'), isFalse);
    });

    test('dado apellido vacío → completo y otro nombre, tampoco: completar no es cambiar', () {
      expect(parece(persona(apellido: ''), 'Roberto', 'Suárez'), isFalse);
      expect(parece(persona(apellido: '   '), 'Roberto', 'Suárez'), isFalse);
    });

    test('dado apellido vacío que sigue vacío, no sale el aviso', () {
      expect(parece(persona(apellido: ''), 'Roberto', ''), isFalse);
    });
  });

  group('datos límite', () {
    test(
      'dado un nombre con ñ y diéresis, se compara sin tildes pero con las letras distintas',
      () {
        expect(parece(persona(nombre: 'Muñoz', apellido: 'Güemes'), 'Munoz', 'Guemes'), isFalse);
        expect(parece(persona(nombre: 'Muñoz', apellido: 'Güemes'), 'Pérez', 'López'), isTrue);
      },
    );

    test('dado el apellido borrado por completo (con el nombre cambiado), cuenta como cambio', () {
      expect(parece(persona(), 'Roberto', ''), isTrue);
    });
  });
}
