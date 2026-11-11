import 'package:equatable/equatable.dart';

import '../../../mapa/domain/entities/espacio.dart';
import '../../../mapa/domain/entities/persona.dart';
import '../../../mapa/domain/entities/ubicacion.dart';

/// Una persona a la que se le puede vender desde la pestaña Ventas: ella, su vínculo con el espacio
/// (`espacio_persona.id`, lo que la venta guarda) y dónde está (el depto y la ubicación, para la
/// dirección y la ciudad de los precios).
///
/// Solo entran las personas **activas** de espacios y ubicaciones **activos**: una dada de baja es de
/// solo lectura (32B·04) y no se le vende.
///
/// **local-only — PII**: lleva el nombre y el teléfono de la persona (ver `Persona.stringify`).
class PersonaParaVender extends Equatable {
  const PersonaParaVender({
    required this.persona,
    required this.espacioPersonaId,
    required this.espacio,
    required this.ubicacion,
  });

  final Persona persona;

  /// `espacio_persona.id`: con quién y dónde es la venta.
  final String espacioPersonaId;
  final Espacio espacio;
  final Ubicacion ubicacion;

  String get espacioId => espacio.id;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [persona, espacioPersonaId, espacio, ubicacion];
}
