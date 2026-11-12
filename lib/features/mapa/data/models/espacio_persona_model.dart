import '../../domain/entities/espacio_persona.dart';
import 'auditoria_json.dart';

/// DTO de [EspacioPersona]. [toJson] usa los nombres de columna de `public.espacio_persona`
/// (`backend-supabase`, migración 0001) y es el payload del sync: **solo ids** y auditoría, nunca un
/// dato de la persona (ADR-017; la persona ni siquiera existe del lado del servidor).
final class EspacioPersonaModel extends EspacioPersona {
  const EspacioPersonaModel({
    required super.id,
    required super.espacioId,
    required super.personaId,
    super.ubicacionCobranzaAltId,
    required super.auditoria,
  });

  factory EspacioPersonaModel.fromEntity(EspacioPersona vinculo) => EspacioPersonaModel(
    id: vinculo.id,
    espacioId: vinculo.espacioId,
    personaId: vinculo.personaId,
    ubicacionCobranzaAltId: vinculo.ubicacionCobranzaAltId,
    auditoria: vinculo.auditoria,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'espacio_id': espacioId,
    'persona_id': personaId,
    'ubicacion_cobranza_alt_id': ubicacionCobranzaAltId,
    ...auditoriaAJson(auditoria),
  };
}
