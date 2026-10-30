import 'package:equatable/equatable.dart';

import 'contexto_notas_persona.dart';
import 'persona.dart';

/// La persona que se va a editar (HU-UBI-010, vista 32C) y si se la puede cambiar.
///
/// **PII**: lleva el nombre, el apellido y el teléfono, y la dirección de su espacio; no se imprime ni
/// va a los logs (`stringify` apagado).
class ContextoEdicionPersona extends Equatable {
  const ContextoEdicionPersona({
    required this.persona,
    this.espacioId,
    this.causa,
    this.bajaDesde,
    this.numeroDepto,
    this.direccion,
  });

  /// Cómo está hoy en el teléfono.
  final Persona persona;

  /// El espacio donde está hoy («Mataojo 2044 · Depto 3B»), si tiene uno vigente.
  final String? espacioId;

  /// Por qué solo se puede ver (32B·04 y 32B·08); `null` si se puede editar.
  final CausaSoloLectura? causa;

  /// Cuándo se la dio de baja (con [CausaSoloLectura.personaDeBaja]).
  final DateTime? bajaDesde;

  /// El número del depto dado de baja (con [CausaSoloLectura.espacioDeBaja]), si tiene.
  final String? numeroDepto;

  /// «Mataojo 2044»: dónde está el espacio dado de baja, si se conoce.
  final String? direccion;

  /// La persona está dada de baja, o ningún espacio suyo sigue activo: sus datos se ven, pero no se
  /// cambian.
  bool get soloLectura => causa != null;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [persona, espacioId, causa, bajaDesde, numeroDepto, direccion];
}
