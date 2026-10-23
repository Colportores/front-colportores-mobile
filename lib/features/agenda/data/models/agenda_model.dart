import '../../../mapa/data/models/auditoria_json.dart';
import '../../domain/entities/agenda.dart';

/// DTO de [Agenda]: la entidad más su payload de sync. [toJson] usa los nombres de columna de
/// `public.agenda` (`backend-supabase`, migración 0001) y las fechas en ISO-8601 UTC: es la fila
/// entera, lo que se encola. Un test fija la lista exacta de claves contra las columnas de la tabla
/// local para que no se cuele ninguna (y menos una nota, que es local-only).
final class AgendaModel extends Agenda {
  AgendaModel({
    required super.id,
    required super.espacioPersonaId,
    required super.tipo,
    required super.fechaProgramada,
    super.slotCodigo,
    super.esEstricta,
    super.ubicacionAltId,
    super.estado,
    required super.colportorId,
    super.visitaId,
    required super.auditoria,
  });

  factory AgendaModel.fromEntity(Agenda agenda) => AgendaModel(
    id: agenda.id,
    espacioPersonaId: agenda.espacioPersonaId,
    tipo: agenda.tipo,
    fechaProgramada: agenda.fechaProgramada,
    slotCodigo: agenda.slotCodigo,
    esEstricta: agenda.esEstricta,
    ubicacionAltId: agenda.ubicacionAltId,
    estado: agenda.estado,
    colportorId: agenda.colportorId,
    visitaId: agenda.visitaId,
    auditoria: agenda.auditoria,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'espacio_persona_id': espacioPersonaId,
    'tipo': tipo.codigo,
    'fecha_programada': fechaProgramada.toIso8601String(),
    'slot_codigo': slotCodigo,
    'es_estricta': esEstricta,
    'ubicacion_alt_id': ubicacionAltId,
    'estado': estado.codigo,
    'colportor_id': colportorId,
    'visita_id': visitaId,
    ...auditoriaAJson(auditoria),
  };
}
