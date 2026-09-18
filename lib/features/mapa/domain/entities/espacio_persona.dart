import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Asociación M:N persona ↔ espacio, con ubicación alternativa de cobranza opcional
/// (esquema-datos.md §Modelo de Espacio, tabla `espacio_persona`).
class EspacioPersona extends Equatable {
  const EspacioPersona({
    required this.id,
    required this.espacioId,
    required this.personaId,
    this.ubicacionCobranzaAltId,
    required this.auditoria,
  });

  final String id;

  /// FK a `espacio.id`.
  final String espacioId;

  /// FK a `persona.id`.
  final String personaId;

  /// FK opcional a `ubicacion.id` — caso "negocio con cobranza en casa"
  /// (esquema-datos.md, "Pendientes / a decidir": vive acá, no en `agenda`).
  final String? ubicacionCobranzaAltId;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  @override
  List<Object?> get props => [id, espacioId, personaId, ubicacionCobranzaAltId, auditoria];
}
