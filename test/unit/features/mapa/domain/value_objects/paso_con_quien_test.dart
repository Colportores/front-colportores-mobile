// Qué pide el paso «¿Con quién?» de la vista 39 según las personas del espacio (HU-VIS-005, contratos
// de navegación de la 39): sin personas el nombre, con una el paso se salta, con varias la lista.
import 'package:colportores_mobile/features/mapa/domain/entities/persona_de_la_entrevista.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/paso_con_quien.dart';
import 'package:test/test.dart';

import '../../../../../helpers/persona_falsos.dart';

void main() {
  final pedro = clienteDePersonas('pedro', 'Pedro', apellido: 'Gómez');
  final ana = clienteDePersonas('ana', 'Ana', apellido: 'Gómez', minutos: 1);

  group('PasoConQuien.de', () {
    test('dado un espacio sin personas, cuando se decide el paso, pide el nombre (R·04)', () {
      expect(PasoConQuien.de(const []), isA<SinPersonas>());
    });

    test('dado una sola persona, cuando se decide el paso, se salta y la elige', () {
      final paso = PasoConQuien.de([pedro]);

      expect(paso, isA<UnaPersona>());
      expect(
        (paso as UnaPersona).elegida,
        const PersonaDeLaEntrevista(personaId: 'pedro', espacioPersonaId: 'ep-pedro'),
      );
    });

    test('dado dos o más personas, cuando se decide el paso, ofrece la lista en el mismo orden '
        '(C·07)', () {
      final paso = PasoConQuien.de([pedro, ana]);

      expect(paso, isA<VariasPersonas>());
      expect((paso as VariasPersonas).personas, [pedro, ana]);
    });

    test('la lista del paso no se puede modificar por afuera', () {
      final origen = [pedro, ana];
      final paso = PasoConQuien.de(origen) as VariasPersonas;
      origen.add(clienteDePersonas('x', 'Xavier'));

      expect(paso.personas, hasLength(2));
      expect(() => paso.personas.add(pedro), throwsUnsupportedError);
    });
  });

  group('PersonaDeLaEntrevista', () {
    test('lleva el vínculo con el espacio, no solo la persona (la visita se guarda contra él)', () {
      expect(pedro.aLaEntrevista.personaId, 'pedro');
      expect(pedro.aLaEntrevista.espacioPersonaId, 'ep-pedro');
    });

    test('dos con los mismos ids son iguales', () {
      expect(
        pedro.aLaEntrevista,
        const PersonaDeLaEntrevista(personaId: 'pedro', espacioPersonaId: 'ep-pedro'),
      );
      expect(pedro.aLaEntrevista, isNot(ana.aLaEntrevista));
    });
  });
}
