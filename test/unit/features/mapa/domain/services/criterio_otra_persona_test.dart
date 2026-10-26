// HU-UBI-010, caso borde «Cambio total de nombre» (canvas 32C·03): la regla de cuándo un cambio parece
// «otra persona» está pendiente («Cristian §3: regla de negocio»). Mientras tanto, el criterio por
// defecto no sugiere nada.
import 'package:colportores_mobile/features/mapa/domain/entities/persona.dart';
import 'package:colportores_mobile/features/mapa/domain/services/criterio_otra_persona.dart';
import 'package:test/test.dart';

import '../../../../../helpers/persona_falsos.dart';

void main() {
  final maria = Persona(
    id: 'per-1',
    nombre: 'María',
    apellido: 'Fernández',
    telefono: '099 123 456',
    auditoria: auditoriaPersonas(),
  );

  test('dado el cambio total del canvas (Roberto Suárez, otro teléfono), cuando se pregunta si es '
      'otra persona, el criterio sin definir dice que no', () {
    const criterio = CriterioOtraPersonaSinDefinir();

    final parece = criterio.pareceOtraPersona(maria, (
      nombre: 'Roberto',
      apellido: 'Suárez',
      telefono: '091 222 333',
    ));

    expect(parece, isFalse);
  });

  test('dado cualquier cambio, cuando se pregunta, nunca frena a la colportora', () {
    const criterio = CriterioOtraPersonaSinDefinir();
    final cambios = <DatosDePersona>[
      (nombre: 'María', apellido: 'Fernández', telefono: ''),
      (nombre: '', apellido: '', telefono: ''),
      (nombre: 'Ñ', apellido: 'X', telefono: '+54 9 11 5555 1234'),
    ];

    for (final despues in cambios) {
      expect(criterio.pareceOtraPersona(maria, despues), isFalse);
    }
  });
}
