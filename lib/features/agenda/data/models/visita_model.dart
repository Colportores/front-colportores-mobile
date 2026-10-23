import '../../../mapa/data/models/auditoria_json.dart';
import '../../domain/entities/visita.dart';

/// DTO de [Visita]: la entidad más su payload de sync. [toJson] usa los nombres de columna de
/// `public.visita` (`backend-supabase`, migración 0001) y las fechas en ISO-8601 UTC: es la fila
/// entera, lo que se encola. Un test fija la lista exacta de claves contra las columnas de la tabla
/// local.
final class VisitaModel extends Visita {
  VisitaModel({
    required super.id,
    required super.espacioPersonaId,
    required super.fecha,
    required super.tipoResultado,
    required super.colportorId,
    super.jornadaId,
    required super.auditoria,
  });

  factory VisitaModel.fromEntity(Visita visita) => VisitaModel(
    id: visita.id,
    espacioPersonaId: visita.espacioPersonaId,
    fecha: visita.fecha,
    tipoResultado: visita.tipoResultado,
    colportorId: visita.colportorId,
    jornadaId: visita.jornadaId,
    auditoria: visita.auditoria,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'espacio_persona_id': espacioPersonaId,
    'fecha': fecha.toIso8601String(),
    'tipo_resultado': tipoResultado.codigo,
    'colportor_id': colportorId,
    'jornada_id': jornadaId,
    ...auditoriaAJson(auditoria),
  };
}
