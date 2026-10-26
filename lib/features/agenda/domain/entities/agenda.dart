import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';
import 'estado_agenda.dart';
import 'tipo_agenda.dart';

/// Visita planificada (esquema-datos.md §Operaciones de campo, tabla `agenda`).
///
/// Son las columnas de `public.agenda` (backend-supabase 0001), que la app sube enteras. **No lleva
/// notas**: las de una agenda son filas de `nota` (`target_type = AGENDA`, local-only, ADR-017), así
/// que acá no hay ningún dato personal: solo ids.
class Agenda extends Equatable {
  Agenda({
    required this.id,
    required this.espacioId,
    this.espacioPersonaId,
    required this.tipo,
    required DateTime fechaProgramada,
    this.slotCodigo,
    this.esEstricta = false,
    this.ubicacionAltId,
    this.estado = EstadoAgenda.programada,
    required this.colportorId,
    this.visitaId,
    required this.auditoria,
  }) : fechaProgramada = instanteMs(fechaProgramada);

  /// UUID v7 generado en el dispositivo (esquema-datos.md §Principios 2).
  final String id;

  /// FK a `espacio.id`: la casa o el depto de la cita (backend-supabase 0068).
  final String espacioId;

  /// FK opcional a `espacio_persona.id`: con quién es la cita. Sin persona la cita cuelga solo del
  /// espacio (decisión del 23/10, «Sin persona»).
  final String? espacioPersonaId;

  final TipoAgenda tipo;

  /// Siempre en UTC y al milisegundo — ver [instanteMs].
  final DateTime fechaProgramada;

  /// Código del slot horario recomendado (§8.5.2: `early_morning`, `mid_morning`…), si lo hay.
  final String? slotCodigo;

  /// «Entrevista estricta»: hora fija acordada con el cliente (§8.5.2).
  final bool esEstricta;

  /// FK opcional a `ubicacion.id`: cobranza en otra dirección.
  final String? ubicacionAltId;

  final EstadoAgenda estado;

  /// FK a `usuario.id`.
  final String colportorId;

  /// FK a `visita.id`: se completa al registrar la visita que la cumple.
  final String? visitaId;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  /// Una agenda que sigue esperando su visita (la que pinta la casa de «entrevista programada»).
  bool get estaProgramada => estado == EstadoAgenda.programada && !estaBorrada;

  @override
  List<Object?> get props => [
    id,
    espacioId,
    espacioPersonaId,
    tipo,
    fechaProgramada,
    slotCodigo,
    esEstricta,
    ubicacionAltId,
    estado,
    colportorId,
    visitaId,
    auditoria,
  ];
}
