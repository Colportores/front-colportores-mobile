import '../entities/persona_de_la_entrevista.dart';
import '../entities/persona_del_espacio.dart';

/// Qué pide el paso «¿Con quién?» de la vista 39 según las personas que tiene el espacio (HU-VIS-005,
/// contratos de navegación de la 39: «con una sola persona el paso de elegir se salta»). Dart puro.
sealed class PasoConQuien {
  const PasoConQuien();

  /// El paso que corresponde a [personas], las activas del espacio.
  factory PasoConQuien.de(List<PersonaDelEspacio> personas) => switch (personas.length) {
    0 => const SinPersonas(),
    1 => UnaPersona(personas.single),
    _ => VariasPersonas(List.unmodifiable(personas)),
  };
}

/// Casa nueva o sin gente cargada (R·04): se pide el nombre y con eso alcanza.
final class SinPersonas extends PasoConQuien {
  const SinPersonas();
}

/// Una sola persona: no hay nada que elegir, el paso se salta.
final class UnaPersona extends PasoConQuien {
  const UnaPersona(this.persona);

  final PersonaDelEspacio persona;

  /// Lo que el paso entrega cuando se salta.
  PersonaDeLaEntrevista get elegida => persona.aLaEntrevista;
}

/// Dos o más (C·07): se elige de la lista o se suma «+ Alguien nuevo».
final class VariasPersonas extends PasoConQuien {
  const VariasPersonas(this.personas);

  final List<PersonaDelEspacio> personas;
}

extension ElegirParaLaEntrevista on PersonaDelEspacio {
  /// La persona con su vínculo, como la recibe quien abrió el paso.
  PersonaDeLaEntrevista get aLaEntrevista =>
      PersonaDeLaEntrevista(personaId: persona.id, espacioPersonaId: vinculo.id);
}
