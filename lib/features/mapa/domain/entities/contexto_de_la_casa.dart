import 'package:equatable/equatable.dart';

import 'nota_del_lugar.dart';
import 'persona_del_espacio.dart';

/// Lo que la hoja de la casa (vista 39, C·01) sabe además de la ubicación: de qué espacio habla, quién
/// vive ahí, cuánto debe y la nota más reciente del lugar.
///
/// En un edificio el contexto es siempre el depto (`espacio_id`), nunca el edificio entero (39,
/// «Reglas comunes»): sin un depto elegido [espacioId] es `null` y no hay personas.
class ContextoDeLaCasa extends Equatable {
  const ContextoDeLaCasa({
    this.espacioId,
    this.personas = const [],
    this.saldosCentavos = const {},
    this.nota,
  });

  /// El espacio de una casa o un negocio (el que el alta crea solo); `null` en un edificio, que
  /// elige un depto (C·09), o si la ubicación no tiene ningún espacio activo.
  final String? espacioId;

  /// Las personas activas del espacio, de la más vieja a la más nueva.
  final List<PersonaDelEspacio> personas;

  /// Lo que debe cada persona (`persona.id` → centavos). Quien no está en el mapa no tiene saldo
  /// conocido: no se muestra nada, ni «$ 0».
  final Map<String, int> saldosCentavos;

  /// La nota más reciente del lugar, si hay.
  final NotaDelLugar? nota;

  /// La persona que muestra el resumen: la que más debe (con saldo mayor a cero); si nadie debe, la
  /// primera. Las demás se ven en la pestaña Personas (C·02). `null` sin personas.
  PersonaDelEspacio? get personaDestacada {
    PersonaDelEspacio? mejor;
    var saldoMejor = 0;
    for (final candidata in personas) {
      final saldo = saldosCentavos[candidata.persona.id] ?? 0;
      if (saldo > saldoMejor) {
        mejor = candidata;
        saldoMejor = saldo;
      }
    }
    return mejor ?? (personas.isEmpty ? null : personas.first);
  }

  /// Lo que debe [personaId] si se sabe y es más que cero; si no, `null`.
  int? saldoDe(String personaId) {
    final saldo = saldosCentavos[personaId];
    return saldo != null && saldo > 0 ? saldo : null;
  }

  /// Lleva datos personales (personas y nota): ver `Persona.stringify`.
  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [espacioId, personas, saldosCentavos, nota];
}
